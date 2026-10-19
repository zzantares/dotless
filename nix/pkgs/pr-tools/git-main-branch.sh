# shellcheck shell=bash

# Get the default branch name from common branch names or fallback to remote HEAD

# If we're not in a git repo nothing to do.
if ! git rev-parse --git-dir &>/dev/null; then
	echo "Not a git repo." >&2
	exit 1
fi

declare remote ref

for ref in refs/{heads,remotes/{origin,upstream}}/{main,trunk,mainline,default,stable,master}; do
	if git show-ref -q --verify "$ref"; then
		git rev-parse --abbrev-ref "${ref}"
		exit 0
	fi
done

# Fallback: try to get the default branch from remote HEAD symbolic refs
for remote in origin upstream; do
	ref="$(git rev-parse --abbrev-ref $remote/HEAD 2>/dev/null)"
	if [[ "$ref" =~ ^${remote}/ ]]; then
		echo "${ref#"${remote}"/}"
		exit 0
	fi
done

# If no main branch was found, fall back to master but return error
echo master
exit 1
