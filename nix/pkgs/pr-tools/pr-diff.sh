# shellcheck shell=bash

# pr-diff - review a GitHub pull request in diffnav, from the PR's own worktree.
#
# Usage:
#   pr-diff <owner/repo>#<number>
#
# Bound to `d` in gh-dash (dotless's devstation preset). diffnav resolves `o`
# (open in editor) against `git rev-parse --show-toplevel` of its own working
# directory, so a PR reviewed from an unrelated checkout opens that checkout's
# copy of the file, never the revision on screen. Checking the PR out first and
# starting diffnav from inside it makes `o` land on the right file, editable.
#
# The checkout is `git pr`, which owns all of it: finding the clone the URL
# names, the sibling worktree on the PR's own source branch, and the ticket key
# its directory is filed under. See that script for the tracker credentials.

die() {
	echo "pr-diff: $*" >&2
	exit 1
}

usage() {
	cat >&2 <<'EOF'
usage:
  pr-diff <owner/repo>#<number>    e.g. pr-diff dlvhdr/gh-dash#447
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

pr_url="https://github.com/$repo/pull/$pr"

# Captured, so git-pr stays a pure path emitter: no session and no editor
# workspace get built just to read a diff. Run `git pr` yourself for those.
# Its progress chatter is already on stderr.
dest="$(git pr "$pr_url")" || die "could not check out $repo#$pr"

cd "$dest" || die "cannot enter $dest"
exec diffnav --pr "$pr_url"
