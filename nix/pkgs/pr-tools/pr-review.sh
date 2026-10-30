# shellcheck shell=bash

# pr-review - review a GitHub pull request in nvim, from the PR's own worktree.
#
# Usage:
#   pr-review <owner/repo>#<number>
#
# Bound to `R` in gh-dash (dotless's devstation preset), the writing half of
# what `d` shows: octo.nvim for inline comments, suggestions, approve and
# request-changes. nvim deliberately, whatever GIT_PR_EDITOR says elsewhere -
# `nitpick` is the Emacs review path and keeps its own bindings.
#
# The checkout is `git pr`, the same worktree `d` sends diffnav into, so both
# keys land on one checkout at the PR head. octo is configured use_local_fs,
# which makes the right-hand side of the review read those files instead of
# fetched blobs: LSP and treesitter work, and an edit is a real edit.
#
# Opens the PR buffer; start the review from there (`Octo review start`), so a
# glance at a PR does not open a pending review on it.

die() {
	echo "pr-review: $*" >&2
	exit 1
}

usage() {
	cat >&2 <<'EOF'
usage:
  pr-review <owner/repo>#<number>    e.g. pr-review dlvhdr/gh-dash#447
EOF
}

spec="${1:-}"
case "$spec" in
	-h | --help)
		usage
		exit 0
		;;
	*/*#*) ;;
	*)
		usage
		exit 2
		;;
esac

repo="${spec%%#*}"
pr="${spec##*#}"
[[ "$pr" =~ ^[0-9]+$ ]] || die "expected a PR number, got '$pr'"

have() { command -v "$1" >/dev/null 2>&1; }
have nvim || die "nvim is not on PATH"

# Captured, so git-pr stays a pure path emitter: the session and editor
# workspace it builds when run bare would fight the nvim we are about to start.
dest="$(git pr "https://github.com/$repo/pull/$pr")" || die "could not check out $repo#$pr"

cd "$dest" || die "cannot enter $dest"
exec nvim -c "Octo pr edit $pr"
