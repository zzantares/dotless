# shellcheck shell=bash
#
# Multiplexer backends for the workspace scripts (git-wt, git-pr, task):
#
#   source "$HOME/.local/lib/sh/mux.sh"   # git half: ./worktree.sh
#
# A "session" is a tmux session or a wezterm workspace. Which one a call lands on
# is decided per invocation by mux_backend, so both work side by side.
#
# Asymmetric on purpose: create and switch reach only the backend you are sitting
# in, because you cannot open or enter a multiplexer you are not running. Find and
# kill reach every backend, because a session may have been created from the other
# one.
#
# Helpers stay quiet and return status codes; each caller owns its messages.

[[ -n "${_DOTLESS_MUX_SH:-}" ]] && return 0
_DOTLESS_MUX_SH=1

# tmux|wezterm|none. DOTLESS_WT_BACKEND overrides the probe.
# tmux is probed first: tmux inside wezterm sets both variables, and the innermost
# multiplexer owns the session you are in.
mux_backend() {
	case "${DOTLESS_WT_BACKEND:-auto}" in
		tmux | wezterm | none)
			echo "$DOTLESS_WT_BACKEND"
			return 0
			;;
	esac
	if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
		echo tmux
	elif [[ -n "${WEZTERM_PANE:-}" ]] && command -v wezterm >/dev/null 2>&1; then
		echo wezterm
	else
		echo none
	fi
}

# Whether <backend> can be reached right now, regardless of where we are sitting.
# Used by the fan-out helpers, which must ask backends we are not running under.
_mux_reachable() {
	case "$1" in
		tmux) command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1 ;;
		wezterm) command -v wezterm >/dev/null 2>&1 && wezterm cli list >/dev/null 2>&1 ;;
		*) return 1 ;;
	esac
}

# ---------------------------------------------------------------- tmux backend

_mux_tmux_has() { tmux has-session -t "$1" 2>/dev/null; }

_mux_tmux_ensure() {
	local session=$1 dir=$2
	_mux_tmux_has "$session" && return 1
	tmux new-session -d -s "$session" -c "$dir" 2>/dev/null && return 0 || return 2
}

_mux_tmux_switch() {
	local session=$1
	if [[ -n "${TMUX:-}" ]]; then
		tmux switch-client -t "$session" 2>/dev/null
	else
		tmux attach-session -t "$session"
	fi
}

_mux_tmux_kill() {
	_mux_tmux_has "$1" || return 1
	tmux kill-session -t "$1" 2>/dev/null
}

_mux_tmux_new_window() {
	local session=$1 dir=$2 title=$3
	shift 3
	tmux new-window -t "$session" -c "$dir" -n "$title" "$@"
}

_mux_tmux_send() { tmux send-keys -t "$1" "$2" Enter; }

_mux_tmux_current() { tmux display-message -p '#S' 2>/dev/null; }

# ------------------------------------------------------------- wezterm backend

# Pane ids in <workspace>, newest last. Empty when the workspace does not exist:
# wezterm has no workspace list of its own, a workspace exists iff a pane is in it.
_mux_wez_panes() {
	wezterm cli list --format json 2>/dev/null |
		jq -r --arg w "$1" '.[] | select(.workspace == $w) | .pane_id' 2>/dev/null
}

_mux_wez_has() { [[ -n "$(_mux_wez_panes "$1")" ]]; }

# Creates the workspace without activating it: wezterm only renders the active
# workspace, so the new window stays hidden. Same intent as a detached session.
_mux_wez_ensure() {
	local ws=$1 dir=$2
	_mux_wez_has "$ws" && return 1
	wezterm cli spawn --new-window --workspace "$ws" --cwd "$dir" >/dev/null 2>&1 && return 0 || return 2
}

# No CLI command activates a workspace (`activate-pane` exits 0 and does nothing),
# so the switch goes through the GUI: an OSC 1337 user var the wezterm.lua handler
# turns into SwitchToWorkspace. Written to /dev/tty because stdout may be captured.
#
# The workspace always exists by here (callers ensure first), so the handler never
# takes the spawn path - the one that stalls the repaint.
_mux_wez_switch() {
	local ws=$1 payload
	# `base64 -w0` is GNU-only; tr keeps this working on macOS.
	payload="$(printf '%s\t' "$ws" | base64 | tr -d '\n')"
	printf '\033]1337;SetUserVar=switch-workspace=%s\a' "$payload" >/dev/tty 2>/dev/null
}

_mux_wez_kill() {
	local ws=$1 pane killed=1
	_mux_wez_has "$ws" || return 1
	while read -r pane; do
		[[ -n "$pane" ]] || continue
		wezterm cli kill-pane --pane-id "$pane" >/dev/null 2>&1 && killed=0
	done < <(_mux_wez_panes "$ws")
	return $killed
}

# A tab in the workspace's first window, so it shares the workspace.
_mux_wez_new_window() {
	local ws=$1 dir=$2 title=$3 pane win
	shift 3
	pane="$(_mux_wez_panes "$ws" | head -1)"
	[[ -n "$pane" ]] || return 1
	win="$(wezterm cli list --format json 2>/dev/null |
		jq -r --argjson p "$pane" '.[] | select(.pane_id == $p) | .window_id' 2>/dev/null)"
	[[ -n "$win" ]] || return 1
	pane="$(wezterm cli spawn --window-id "$win" --cwd "$dir" -- "$@" 2>/dev/null)" || return 1
	wezterm cli set-tab-title --pane-id "$pane" "$title" >/dev/null 2>&1 || true
}

# --no-paste plus a trailing newline is the equivalent of send-keys ... Enter;
# a bracketed paste would leave the line sitting unsubmitted.
_mux_wez_send() {
	local pane
	pane="$(_mux_wez_panes "$1" | head -1)"
	[[ -n "$pane" ]] || return 1
	printf '%s\n' "$2" | wezterm cli send-text --pane-id "$pane" --no-paste
}

_mux_wez_current() {
	wezterm cli list-clients --format json 2>/dev/null |
		jq -r '.[0].workspace // empty' 2>/dev/null
}

# ------------------------------------------------- public API: current backend

# Idempotent session <name> rooted at <dir>, in the backend you are sitting in.
# Returns: 0 newly created, 1 already existed, 2 no backend / create failed.
mux_ensure_session() {
	case "$(mux_backend)" in
		tmux) _mux_tmux_ensure "$1" "$2" ;;
		wezterm) _mux_wez_ensure "$1" "$2" ;;
		*) return 2 ;;
	esac
}

# Switch/attach the caller into <name>. Non-zero when the backend cannot do it.
mux_switch() {
	case "$(mux_backend)" in
		tmux) _mux_tmux_switch "$1" ;;
		wezterm) _mux_wez_switch "$1" ;;
		*) return 1 ;;
	esac
}

# A window/tab inside <name> rooted at <dir>, titled <title>, running the rest.
mux_new_window() {
	case "$(mux_backend)" in
		tmux) _mux_tmux_new_window "$@" ;;
		wezterm) _mux_wez_new_window "$@" ;;
		*) return 1 ;;
	esac
}

# Run <text> as a command line in <name>'s first pane.
mux_send() {
	case "$(mux_backend)" in
		tmux) _mux_tmux_send "$1" "$2" ;;
		wezterm) _mux_wez_send "$1" "$2" ;;
		*) return 1 ;;
	esac
}

# Name of the session/workspace the caller is sitting in, or empty.
mux_current_session() {
	case "$(mux_backend)" in
		tmux) _mux_tmux_current ;;
		wezterm) _mux_wez_current ;;
		*) return 1 ;;
	esac
}

# ---------------------------------------------------- public API: every backend

# Backends that hold a session named <name>, one per line. Empty when none do.
mux_find() {
	local name=$1
	_mux_reachable tmux && _mux_tmux_has "$name" && echo tmux
	_mux_reachable wezterm && _mux_wez_has "$name" && echo wezterm
	return 0
}

# Kill <name> wherever it lives. Returns 0 iff something was killed - a worktree
# started from tmux must still be cleaned up from wezterm, and the reverse.
mux_kill() {
	local name=$1 killed=1
	if _mux_reachable tmux && _mux_tmux_kill "$name"; then killed=0; fi
	if _mux_reachable wezterm && _mux_wez_kill "$name"; then killed=0; fi
	return $killed
}
