# shellcheck shell=bash
#
# Shared primitives for the worktree-workspace scripts (git-wt, git-pr, task)
# across repos. dotless ships this to a stable path via its dotfiles home-manager
# module, so consumers source it by absolute path:
#
#   source "$HOME/.local/lib/worktree.sh"
#
# Helpers stay quiet and return status codes; each caller owns its user-facing
# messages (and its own "git wt:" / "git pr:" / task prefix). Unavoidable
# git/tmux output is routed to stderr so a caller's stdout can stay a pure path
# emitter. The Emacs helpers are cross-platform (Linux systemd + macOS launchd).

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

# Root where sibling worktrees live: the dir containing the git common dir.
wt_worktree_root() { dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)"; }

# origin/<main> when that ref exists, else the bare local <main>.
wt_resolve_base() {
	if git show-ref -q --verify "refs/remotes/origin/$1"; then echo "origin/$1"; else echo "$1"; fi
}

# Path of the worktree checked out on <branch>, or empty.
wt_for_branch() {
	git worktree list --porcelain | awk -v ref="refs/heads/$1" '
		/^worktree / { wt = substr($0, 10) }
		$1 == "branch" && $2 == ref { print wt; exit }'
}

# Whether <branch> has merged into <base>: tip is an ancestor (merge commit /
# fast-forward) or every commit is patch-equivalent upstream (rebase merge, which
# git cherry marks with '-', unmerged with '+'). Squash merges rewrite patch-ids
# and so are not detected.
wt_is_merged() {
	local branch=$1 base=$2 cherry
	git merge-base --is-ancestor "$branch" "$base" 2>/dev/null && return 0
	cherry="$(git cherry "$base" "$branch" 2>/dev/null)" || return 1
	[[ -n "$cherry" ]] && ! grep -q '^+' <<<"$cherry"
}

# Idempotent worktree at <dest> on <branch>, created from <start> when new.
# Echoes the final path (an existing checkout of <branch> wins over <dest>);
# git/worktree chatter goes to stderr so stdout carries only that path.
wt_add() {
	local dest=$1 branch=$2 start=$3 existing
	existing="$(wt_for_branch "$branch")"
	if [[ -n "$existing" ]]; then
		echo "$existing"
		return 0
	fi
	if git worktree list --porcelain | grep -qxF "worktree $dest"; then
		: # dest is already a worktree (e.g. an earlier run) - reuse it
	elif [[ -e "$dest" ]]; then
		echo "wt_add: '$dest' exists and is not a worktree" >&2
		return 1
	elif git show-ref -q --verify "refs/heads/$branch"; then
		git worktree add "$dest" "$branch" >&2
	else
		git worktree add -b "$branch" "$dest" "$start" >&2
	fi
	command -v zoxide >/dev/null 2>&1 && zoxide add "$dest" >/dev/null 2>&1 || true
	echo "$dest"
}

# Idempotent detached tmux session <session> rooted at <dir>.
# Returns: 0 newly created, 1 already existed, 2 tmux unavailable / create failed.
wt_ensure_tmux() {
	local session=$1 dir=$2
	command -v tmux >/dev/null 2>&1 || return 2
	tmux has-session -t "$session" 2>/dev/null && return 1
	tmux new-session -d -s "$session" -c "$dir" 2>/dev/null && return 0 || return 2
}

# Switch/attach the caller into <session>: switch-client inside tmux, else attach.
wt_tmux_switch() {
	local session=$1
	command -v tmux >/dev/null 2>&1 || return 0
	if [[ -n "${TMUX:-}" ]]; then
		tmux switch-client -t "$session" 2>/dev/null || true
	else
		tmux attach-session -t "$session"
	fi
}

# Kill tmux session <session> if it exists. Returns 0 iff a session was killed.
wt_tmux_kill() {
	local session=$1
	command -v tmux >/dev/null 2>&1 || return 1
	tmux has-session -t "$session" 2>/dev/null || return 1
	tmux kill-session -t "$session" 2>/dev/null
}

# nvim in its own tmux window (a TUI, so it shares the session): (<session> <dir>).
wt_open_nvim() { tmux new-window -t "$1" -c "$2" -n editor "nvim ."; }

# zed opens <dir> as a project window.
wt_open_zed() { zed "$1" & }

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

# Ensure the Emacs daemon is up AND responsive. Returns 0 when reachable.
# The liveness probe is a bounded ping (portable; `systemctl is-active` is
# Linux-only and cannot detect a wedged-but-loaded daemon). Restarts only when
# start=1: on macOS via the launchd agent, on Linux via the systemd --user unit.
wt_emacs_daemon() {
	command -v emacsclient >/dev/null 2>&1 || return 1
	wt_emacsclient 3 -u --eval t >/dev/null 2>&1 && return 0
	[[ "${1:-0}" == 1 ]] || return 1

	case "$OSTYPE" in
		darwin*)
			# -k kills a wedged-but-loaded daemon before restarting; a plain
			# kickstart no-ops when the service is loaded (but hung).
			launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.emacs" 2>/dev/null || true
			;;
		*)
			systemctl --user restart emacs.service 2>/dev/null || true
			;;
	esac

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
	elisp="(progn (when (fboundp '+workspace/delete) (ignore-errors (+workspace/delete \"$slug\"))) \
		(projectile-remove-known-project \"$dest\"))"
	wt_emacsclient 5 -n --eval "$elisp" >/dev/null 2>&1 || true
}
