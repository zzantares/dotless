# shellcheck shell=bash
#
# Emacs primitives shared by the workspace scripts (git-wt, git-pr, task) and by
# doom-bootstrap. dotless ships this directory to a stable path via its zsh
# home-manager module, so consumers source it by absolute path:
#
#   source "$HOME/.local/lib/sh/emacs.sh"
#
# Every helper is cross-platform: systemd --user on Linux, launchd on macOS.
# Helpers stay quiet and return status codes; each caller owns its messages.

# Sourcing this file twice is harmless for the functions, but the probe below
# would run again - so guard the whole file, the way a C header does.
[[ -n "${_DOTLESS_EMACS_SH:-}" ]] && return 0
_DOTLESS_EMACS_SH=1

# Prefer coreutils timeout(1) to bound emacsclient calls (GNU `timeout` on Linux,
# Homebrew's `gtimeout` on macOS). Empty when neither exists, in which case we
# fall back to emacsclient's own (best-effort) --timeout.
if command -v timeout >/dev/null 2>&1; then
	WT_EC_TIMEOUT="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
	WT_EC_TIMEOUT="gtimeout"
else
	WT_EC_TIMEOUT=""
fi

# emacsclient bounded by a hard external timeout: (<secs> <emacsclient args...>).
# emacsclient's own -w/--timeout does not reliably bound a call once the daemon
# is busy - a wedged daemon (up at the socket but blocked on its single main
# thread) can ignore it and hang forever, which is how one run's project-switch
# can hang the *next* run's liveness ping. timeout(1) guarantees we fail fast;
# we fall back to --timeout only when no timeout(1) is installed.
wt_emacsclient() {
	local secs=$1
	shift
	if [[ -n "$WT_EC_TIMEOUT" ]]; then
		"$WT_EC_TIMEOUT" "$secs" emacsclient "$@"
	else
		emacsclient --timeout="$secs" "$@"
	fi
}

# Force-restart the Emacs daemon: the launchd agent on macOS, the systemd --user
# unit on Linux. Returns non-zero when there is no daemon to restart (e.g. before
# the first activation), so a caller can report that rather than claim a restart.
wt_emacs_restart() {
	case "$OSTYPE" in
		darwin*)
			# -k kills a wedged-but-loaded daemon before restarting; a plain
			# kickstart no-ops when the service is loaded (but hung).
			launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.emacs" 2>/dev/null
			;;
		*)
			systemctl --user cat emacs.service >/dev/null 2>&1 || return 1
			systemctl --user restart emacs.service 2>/dev/null
			;;
	esac
}

# Ensure the Emacs daemon is up AND responsive. Returns 0 when reachable.
# The liveness probe is a bounded ping (portable; `systemctl is-active` is
# Linux-only and cannot detect a wedged-but-loaded daemon). Restarts only when
# start=1: on macOS via the launchd agent, on Linux via the systemd --user unit.
wt_emacs_daemon() {
	command -v emacsclient >/dev/null 2>&1 || return 1
	wt_emacsclient 3 -u --eval t >/dev/null 2>&1 && return 0
	[[ "${1:-0}" == 1 ]] || return 1

	wt_emacs_restart || true

	local _
	for _ in $(seq 1 15); do
		wt_emacsclient 3 -u --eval t >/dev/null 2>&1 && return 0
		sleep 1
	done
	return 1
}

# Register a Doom workspace + projectile project for <dest>:
#   wt_emacs_add <slug> <dest> [start_daemon=0] [switch=0]
# start_daemon ensures/starts the daemon; switch also switches to the project.
# Returns non-zero (a clean no-op) when no daemon is reachable.
#
# When switching, projectile-switch-project-action is bound to projectile-dired:
# Doom's default action runs a find-file completing-read, which in a frameless
# daemon parks the single main thread on a prompt no one can answer, wedging it
# (inhibit-message / ignore-errors do NOT help - a prompt is neither). dired
# opens the project root and never prompts. The body returns a plain `t`.
wt_emacs_add() {
	local slug=$1 dest=$2 start_daemon=${3:-0} switch=${4:-0} elisp
	wt_emacs_daemon "$start_daemon" || return 1

	if [[ "$switch" == 1 ]]; then
		elisp="(let ((inhibit-message t) \
		            (projectile-switch-project-action #'projectile-dired)) \
			(ignore-errors \
				(when (fboundp '+workspace/new) (+workspace/new \"$slug\")) \
				(projectile-add-known-project \"$dest\") \
				(projectile-switch-project-by-name \"$dest\")) \
			t)"
	else
		elisp="(progn \
			(when (fboundp '+workspace/new) (ignore-errors (+workspace/new \"$slug\"))) \
			(projectile-add-known-project \"$dest\") t)"
	fi

	# -n so we don't wait on the return value; the external timeout is the real
	# bound in case the connection stalls.
	wt_emacsclient 10 -n --eval "$elisp" >/dev/null 2>&1
}

# Drop a Doom workspace + projectile project for <dest>. Never starts a daemon.
wt_emacs_remove() {
	local slug=$1 dest=$2 elisp
	command -v emacsclient >/dev/null 2>&1 || return 0
	# persp-kill, not +workspace/delete: in Doom the latter deletes a workspace
	# saved under persp-save-dir and errors on a live one, so the workspace
	# wt_emacs_add created was never actually removed - ignore-errors hid it.
	elisp="(progn (when (and (fboundp 'persp-kill) (member \"$slug\" (persp-names))) \
		(ignore-errors (persp-kill \"$slug\"))) \
		(projectile-remove-known-project \"$dest\"))"
	wt_emacsclient 5 -n --eval "$elisp" >/dev/null 2>&1 || true
}
