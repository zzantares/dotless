# shellcheck shell=bash

# git-wt - start and finish work on a feature branch in its own worktree.
#
# Usage:
#   git wt start <branch>     Create a sibling worktree + branch off the main
#                             branch, a background session, and (if a Doom
#                             daemon is up) a projectile project. Prints the path.
#   git wt finish [branch]    Tear all of that back down once the branch has
#                             merged: remove the worktree, delete the branch,
#                             kill the session, drop the projectile project.
#                             Branch defaults to the one checked out in $PWD.
#
# This is the new-branch counterpart to `git pr` (which checks out an
# existing PR). Shared worktree/mux/emacs primitives come from dotless; nested
# branch names (feat/foo) are flattened into a single directory component
# (feat-foo), and the session / Doom workspace are named <repo>/<slug>.
#
# The session is a tmux session or a wezterm workspace, whichever you are running
# (see mux.sh). Side effects degrade gracefully: session steps are skipped when
# neither is up, and Emacs steps are a no-op unless a Doom daemon is already
# running (they never start one - run `git pr` to start it on demand).

# The worktree/mux/emacs library, in the store. DOTLESS_SH_LIB is exported by
# the wrapper, not the copy the zsh module installs under ~/.local/lib/sh, so
# this works without that module.
# shellcheck source=/dev/null
source "$DOTLESS_SH_LIB/all.sh"

usage() {
	cat >&2 <<'EOF'
usage:
  git wt start <branch>     create a worktree + branch off main, plus a background
                            session and (if a Doom daemon is up) projectile
                            project. Prints the worktree path on stdout.
  git wt finish [branch]    remove the worktree, delete the branch, kill the
                            session and drop the projectile project. Refuses
                            unless the branch has merged into main; -f overrides.
                            Branch defaults to the one checked out in $PWD.
EOF
}

die() {
	echo "git wt: $*" >&2
	exit 1
}

git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"

# timeout(1) bounds the fetch below; macOS ships it as gtimeout via Homebrew.
if command -v timeout >/dev/null 2>&1; then
	FETCH_TIMEOUT="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
	FETCH_TIMEOUT="gtimeout"
else
	FETCH_TIMEOUT=""
fi

# Best-effort refresh of origin's refs; callers fall back to local ones.
# Bounded twice: ConnectTimeout for a host that never answers, timeout(1)
# for a transfer that stalls once open. A failure warns, never hangs.
# Returns non-zero on failure so callers can distrust origin/*.
fetch_origin() {
	local out
	local -a cmd=(git fetch origin --quiet)
	if [[ -n "$FETCH_TIMEOUT" ]]; then
		cmd=("$FETCH_TIMEOUT" 20 "${cmd[@]}")
	fi
	out="$(GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o ConnectTimeout=5" "${cmd[@]}" 2>&1)" || {
		echo "git wt: fetch origin failed, using local refs: ${out:-timed out}" >&2
		return 1
	}
}

# Base ref for branching and merge checks. wt_resolve_base prefers
# origin/<main>, which is right only when the fetch landed; a stale one can be
# months behind. On failure use the local branch, the one master's worktree is on.
resolve_base() {
	local main=$1
	local fetched=1
	fetch_origin || fetched=0
	if [[ "$fetched" -eq 0 ]] && git show-ref -q --verify "refs/heads/$main"; then
		echo "git wt: origin is stale, using local $main" >&2
		echo "$main"
	else
		wt_resolve_base "$main"
	fi
}

cmd_start() {
	local branch="${1:-}"
	[[ -n "$branch" ]] || {
		usage
		exit 1
	}

	local main base root slug dest session
	main="$(git-main-branch 2>/dev/null || echo master)"
	[[ "$branch" == "$main" ]] && die "refusing to start work on the main branch ($main)"

	base="$(resolve_base "$main")"
	root="$(wt_worktree_root)"
	slug="${branch//\//-}"
	dest="$root/$slug"
	session="$(basename "$root")/$slug"

	dest="$(wt_add "$dest" "$branch" "$base")" || exit 1

	# wt_add only wires an upstream when it starts from a remote-tracking ref,
	# so a local base would leave `git status` with no ahead/behind counts.
	if [[ "$base" != origin/* ]] && git show-ref -q --verify "refs/remotes/origin/$main"; then
		git branch --set-upstream-to="origin/$main" "$branch" 2>/dev/null || true
	fi

	# Background session in the worktree - a detached tmux session or a hidden
	# wezterm workspace. Never steals focus, so it is safe to run
	# non-interactively (e.g. from an agent). Enter it later with your switcher.
	mux_ensure_session "$session" "$dest"
	case $? in
		0) echo "git wt: created $(mux_backend) session $session" >&2 ;;
		1) echo "git wt: reusing session $session" >&2 ;;
		2) echo "git wt: no multiplexer running; skipped session $session" >&2 ;;
	esac

	# Register-only, and only against an already-running daemon.
	wt_emacs_add "$slug" "$dest" || echo "git wt: no Emacs daemon; skipped projectile setup" >&2

	echo "$dest"
}

cmd_finish() {
	local force=0 branch=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-f | --force) force=1 ;;
			-*) die "finish: unknown option '$1'" ;;
			*) branch="$1" ;;
		esac
		shift
	done

	# Default to the branch checked out in the current worktree.
	if [[ -z "$branch" ]]; then
		branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
		[[ -n "$branch" ]] || die "finish: could not infer branch; pass one explicitly"
	fi

	local main base root slug dest session
	main="$(git-main-branch 2>/dev/null || echo master)"
	[[ "$branch" == "$main" ]] && die "refusing to finish the main branch ($main)"

	base="$(resolve_base "$main")"

	if [[ "$force" -ne 1 ]] && ! wt_is_merged "$branch" "$base"; then
		die "branch '$branch' does not appear merged into $base; use -f to force"
	fi

	root="$(wt_worktree_root)"
	slug="${branch//\//-}"
	dest="$(wt_for_branch "$branch")"
	[[ -n "$dest" ]] || dest="$root/$slug"
	session="$(basename "$root")/$slug"

	# We cannot remove the worktree we are standing in - step out to the repo root.
	case "$PWD/" in
		"$dest"/*) cd "$root" ;;
	esac

	# Worktree: remove if present. --force only when the caller asked, so we do
	# not silently discard uncommitted work.
	if git worktree list --porcelain | grep -qxF "worktree $dest"; then
		if [[ "$force" -eq 1 ]]; then
			git worktree remove --force "$dest" && echo "git wt: removed worktree $dest" >&2
		elif ! git worktree remove "$dest" 2>/dev/null; then
			die "worktree $dest has changes; commit/stash them or re-run with -f"
		else
			echo "git wt: removed worktree $dest" >&2
		fi
	fi

	# Branch: -D because a rebase/squash merge leaves the tip un-ancestored, so
	# -d would refuse even though we verified it merged above.
	if git show-ref -q --verify "refs/heads/$branch"; then
		git branch -D "$branch" >&2
	fi

	# Session and Doom workspace/projectile project. mux_kill asks every backend,
	# so a session started under tmux is still cleaned up from wezterm.
	mux_kill "$session" && echo "git wt: killed session $session" >&2
	wt_emacs_remove "$slug" "$dest"
}

sub="${1:-}"
case "$sub" in
	start)
		shift
		cmd_start "$@"
		;;
	finish)
		shift
		cmd_finish "$@"
		;;
	-h | --help | help)
		usage
		exit 0
		;;
	"")
		usage
		exit 1
		;;
	*)
		die "unknown subcommand '$sub' (try: git wt start <branch> | git wt finish [branch])"
		;;
esac
