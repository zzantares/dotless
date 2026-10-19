# shellcheck shell=bash

# git-pr — work with forge pull requests locally.
#
# Usage:
#   git pr <number|pr-url> [remote] [--prefix <text>]
#
# Fetches refs/pull/<number>/head from <remote> (default: origin) and checks the
# PR out in a sibling worktree. The local branch is named after the PR's upstream
# source branch when that can be recovered, so `git push` updates the PR;
# otherwise it falls back to pr/<number>. Prints the worktree path on stdout so
# callers can `cd "$(git pr <number>)"`.
#
# A bare number means a PR of the repo you are standing in. A PR URL names its
# own repo, so it works from anywhere. That clone is looked for in the current
# repo, then at <root>/<owner>/<repo> - the layout this workspace is moving to -
# and failing that by scanning each root for a clone whose remotes match. Roots
# come from GIT_PR_REPO_ROOTS (colon-separated, default ~/workspace), scanned
# GIT_PR_SCAN_DEPTH deep (default 4). The remote that matched becomes the
# default remote. Forge-agnostic: /pull/<n> (GitHub) and /pulls/<n> (Forgejo,
# Gitea, Codeberg) both parse, and all of them serve refs/pull/<n>/head.
#
# The worktree directory, session and editor workspace are named
# <ticket>-<branch>, where <ticket> is the PR's Linear or Jira key, or pr-<n>
# when there is none. The branch itself is never renamed, so `git push` keeps
# working. --prefix overrides <ticket> when the lookup gets it wrong.
#
# Tracker lookup (GitHub PRs only, and skipped entirely without credentials):
#   LINEAR_API_KEY   Linear personal API key, or LINEAR_API_KEY_FILE; the
#                    sops-nix secret is read when neither is set. Linear's
#                    GitHub integration files the PR as an attachment on the
#                    issue, so the PR URL maps straight to PROJ-123.
#   JIRA_BASE_URL    with JIRA_EMAIL and JIRA_API_TOKEN. Jira publishes no
#                    "which issue owns this PR" endpoint - that link lives in
#                    its dev-status store - so a key is read off the PR title
#                    or branch and confirmed to exist.
#
# The upstream branch name is recovered without any API/token by matching the PR
# head commit against the remote's branches. That works for open, same-repo PRs
# whose source branch still exists; forks and closed PRs fall back to pr/<number>.
#
# Idempotent: re-running for a PR that already has a worktree reuses it (even if
# it lives under a different path or is checked out elsewhere) instead of erroring.
#
# Interactive orchestration: when stdout is a terminal, it also sets up a
# workspace and drops you into it — so `cd "$(git pr N)"` (captured
# stdout) stays a pure path emitter, while running it bare wires everything up:
#   - Inside a multiplexer: creates a session for the worktree (launching a Claude
#     PR-review prompt on first setup) and switches the client to it.
#   - Opens an editor workspace for the worktree. GIT_PR_EDITOR selects it:
#     emacs (default, Doom workspace + projectile project) | nvim | zed | none.

usage() {
	cat >&2 <<'EOF'
usage: git pr <number|pr-url> [remote] [--prefix <text>]

Fetch a pull request and check it out in a sibling worktree, on a local branch
matching the PR's upstream branch name (falling back to pr/<number>). Prints the
worktree path on stdout. Remote defaults to origin.

A number means a PR of the current repo. A PR URL (.../pull/<n> or .../pulls/<n>)
names its own: tried at <root>/<owner>/<repo> first, then found by scanning the
GIT_PR_REPO_ROOTS roots. Either way it works from anywhere.

The worktree directory is named <ticket>-<branch> - the PR's Linear or Jira key,
else pr-<number>. The branch keeps its own name. --prefix replaces <ticket>.

When stdout is a terminal it also builds a workspace: a session (with a Claude
review prompt) when run inside tmux or wezterm, plus an editor workspace selected by
GIT_PR_EDITOR (emacs | nvim | zed | none; default emacs).
EOF
}

# The worktree/mux/emacs library, in the store. DOTLESS_SH_LIB is exported by
# the wrapper, not the copy the zsh module installs under ~/.local/lib/sh, so
# this works without that module.
# shellcheck source=/dev/null
source "$DOTLESS_SH_LIB/all.sh"

case "${1:-}" in
	-h | --help | help)
		usage
		exit 0
		;;
	"")
		usage
		exit 1
		;;
	# A number, a URL or a flag: all three belong to the parser below.
	[0-9]* | *://* | *@*:*/* | -*) ;;
	*)
		echo "git pr: expected a PR number or URL, got '$1'" >&2
		exit 1
		;;
esac

repo_roots="${GIT_PR_REPO_ROOTS:-$HOME/workspace}"
scan_depth="${GIT_PR_SCAN_DEPTH:-4}"
linear_key_file="${LINEAR_API_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/sops-nix/secrets/linear_api_key}"

# host/owner/repo for a remote or web URL, lowercased, in any of git's
# spellings; empty when it does not look like one.
url_slug() {
	local u="${1:-}"
	u="${u#*://}"  # scheme
	u="${u#*@}"    # user
	u="${u%/}"
	u="${u%.git}"
	u="${u/://}"   # scp-style host:owner/repo
	[[ "$u" == */*/* && "$u" != */*/*/* ]] || return 0
	echo "${u,,}"
}

# Split a PR URL into "<host/owner/repo> <number>"; empty when it is not one.
# /pull/ is GitHub's spelling, /pulls/ is Forgejo's; both back refs/pull/<n>/head.
parse_pr_url() {
	local u="${1:-}" slug
	# Anything may trail the number: /files and /commits from the PR's own tabs,
	# a #comment anchor, a ?query from a tracking link.
	[[ "$u" =~ ^(.*)/pulls?/([0-9]+)([/#?].*)?$ ]] || return 0
	slug="$(url_slug "${BASH_REMATCH[1]}")"
	[[ -n "$slug" ]] && echo "$slug ${BASH_REMATCH[2]}"
}

# "<dir> <remote>" for the clone serving <host/owner/repo> at the conventional
# <root>/<owner>/<repo>, or nothing. Its remotes are still checked, so a
# same-named repo on another forge parked at that path is not mistaken for this
# one - the scan then gets its turn.
probe_clone() {
	local want="$1" root dir hit
	local -a roots
	IFS=: read -ra roots <<<"$repo_roots"
	for root in "${roots[@]}"; do
		dir="$root/${want#*/}" # drop the host, keep owner/repo
		[[ -e "$dir/.git" ]] || continue
		hit="$(match_remote "$dir" "$want")" && {
			echo "$dir $hit"
			return 0
		}
	done
	return 1
}

# "<dir> <remote>" for the clone serving <host/owner/repo>: the current repo,
# then where the convention says it lives, then a scan for one that happens to
# match. Every remote is considered, so a PR URL pointing at an upstream
# resolves to that remote rather than to origin.
find_clone() {
	local want="$1" root dir hit
	hit="$(match_remote . "$want")" && {
		echo "$(git rev-parse --show-toplevel) $hit"
		return 0
	}

	probe_clone "$want" && return 0

	local -a roots
	IFS=: read -ra roots <<<"$repo_roots"
	for root in "${roots[@]}"; do
		[[ -d "$root" ]] || continue
		while IFS= read -r gitpath; do
			dir="${gitpath%/.git}"
			hit="$(match_remote "$dir" "$want")" && {
				echo "$dir $hit"
				return 0
			}
		done < <(find "$root" -maxdepth "$scan_depth" -name .git -prune 2>/dev/null)
	done
	return 1
}

# host/owner/repo served by <dir>'s <remote>, or empty. Both URL spellings are
# tried: `get-url` applies url.*.insteadOf rewrites, which can point a remote
# somewhere else entirely, while the raw config value misses the reverse case of
# an alias that rewrites *to* the forge.
remote_slug() {
	local dir="$1" name="$2" url slug
	for url in \
		"$(git -C "$dir" config --get "remote.$name.url" 2>/dev/null || true)" \
		"$(git -C "$dir" remote get-url "$name" 2>/dev/null || true)"; do
		slug="$(url_slug "$url")"
		[[ -n "$slug" ]] && {
			echo "$slug"
			return 0
		}
	done
}

# Name of <dir>'s remote serving <host/owner/repo>, origin first.
match_remote() {
	local dir="$1" want="$2" name
	while IFS= read -r name; do
		[[ "$(remote_slug "$dir" "$name")" == "$want" ]] && {
			echo "$name"
			return 0
		}
	done < <(
		echo origin
		git -C "$dir" remote 2>/dev/null | grep -vx origin || true
	)
	return 1
}

# Every named command is on PATH.
have() {
	local c
	for c in "$@"; do command -v "$c" >/dev/null 2>&1 || return 1; done
}

# The Linear API key, from the environment or the sops-nix secret.
linear_key() {
	if [[ -n "${LINEAR_API_KEY:-}" ]]; then
		echo "$LINEAR_API_KEY"
	elif [[ -r "$linear_key_file" ]]; then
		cat "$linear_key_file"
	fi
}

# Linear issue identifier attached to <pr-url>, or empty.
linear_ticket() {
	local url="$1" key query auth
	have jq curl || return 0
	key="$(linear_key)"
	[[ -n "$key" ]] || return 0

	# Personal API keys (lin_api_*) go in Authorization bare; OAuth tokens are
	# the ones that take a Bearer prefix.
	case "$key" in
		lin_api_*) auth="$key" ;;
		*) auth="Bearer $key" ;;
	esac

	query="$(jq -nc --arg url "$url" '{
		query: "query($url: String!) { attachmentsForURL(url: $url) { nodes { issue { identifier } } } }",
		variables: { url: $url }
	}')"

	curl -sS --max-time 10 https://api.linear.app/graphql \
		-H "Authorization: $auth" \
		-H 'Content-Type: application/json' \
		-d "$query" 2>/dev/null |
		jq -r '.data.attachmentsForURL.nodes[]?.issue.identifier // empty' |
		head -n 1
}

# Jira issue key for <owner/repo>#<pr>, or empty.
jira_ticket() {
	local repo="$1" pr="$2" candidate
	have jq curl gh || return 0
	[[ -n "${JIRA_BASE_URL:-}" && -n "${JIRA_EMAIL:-}" && -n "${JIRA_API_TOKEN:-}" ]] || return 0

	candidate="$(gh pr view "$pr" -R "$repo" --json title,headRefName -q '.title + " " + .headRefName' 2>/dev/null |
		grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -n 1)"
	[[ -n "$candidate" ]] || return 0

	curl -sS --max-time 10 -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
		"${JIRA_BASE_URL%/}/rest/api/3/issue/$candidate?fields=key" 2>/dev/null |
		jq -r '.key // empty'
}

# What to file <host/owner/repo>#<pr> under: its tracker key, else pr-<number>.
# Both trackers are reached through GitHub - Linear keys off the PR URL, Jira
# off what `gh` reports - so a PR anywhere else is pr-<number> without asking.
ticket_for() {
	local slug="$1" number="$2" ticket=""
	if [[ "${slug%%/*}" == "github.com" ]]; then
		ticket="$(linear_ticket "https://$slug/pull/$number" || true)"
		[[ -n "$ticket" ]] || ticket="$(jira_ticket "${slug#*/}" "$number" || true)"
	fi
	echo "${ticket:-pr-$number}"
}

prefix=""
positional=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		--prefix)
			[[ $# -ge 2 ]] || {
				echo "git pr: --prefix needs a value" >&2
				exit 1
			}
			prefix="$2"
			shift 2
			;;
		--prefix=*)
			prefix="${1#--prefix=}"
			shift
			;;
		-*)
			echo "git pr: unknown option '$1'" >&2
			exit 1
			;;
		*)
			positional+=("$1")
			shift
			;;
	esac
done

pr="${positional[0]:-}"
remote="${positional[1]:-}"

# A URL carries its own repo, so resolve it to a clone and work from there.
pr_slug=""
if parsed="$(parse_pr_url "$pr")" && [[ -n "$parsed" ]]; then
	read -r pr_slug pr <<<"$parsed"
	if ! clone="$(find_clone "$pr_slug")"; then
		echo "git pr: no clone of $pr_slug under ${repo_roots//:/, } (or \$PWD)" >&2
		exit 1
	fi
	read -r dir matched <<<"$clone"
	cd "$dir"
	remote="${remote:-$matched}"
fi

remote="${remote:-origin}"

if [[ ! "$pr" =~ ^[0-9]+$ ]]; then
	echo "git pr: expected a PR number or URL, got '${positional[0]:-}'" >&2
	exit 1
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
	echo "git pr: not inside a git repository" >&2
	exit 1
fi

pr_ref="refs/pull/$pr/head"

# Resolve the PR head SHA up front: fail early with a clear message, and use it
# below to recover the source branch name.
pr_sha="$(git ls-remote "$remote" "$pr_ref" | awk '{ print $1; exit }')"
if [[ -z "$pr_sha" ]]; then
	echo "git pr: no $pr_ref on '$remote' (is PR #$pr open there?)" >&2
	exit 1
fi

# Recover the PR's source branch by matching its head commit against the remote's
# branches. No match (fork/closed PR) → fall back to pr/<number>.
branch="$(git ls-remote "$remote" 'refs/heads/*' |
	awk -v sha="$pr_sha" '$1 == sha { sub(/^refs\/heads\//, "", $2); print $2; exit }')"
if [[ -z "$branch" ]]; then
	branch="pr/$pr"
fi

# Root new worktrees alongside the repository dir, matching the existing layout.
worktree_root="$(wt_worktree_root)"
# Flatten nested branch names (feat/foo) into a single directory component, and
# file it under the PR's ticket - or whatever --prefix overrode that with. A
# branch that already leads with the ticket is left alone, so ENG-7/fix stays
# ENG-7-fix and the pr-<n> fallback does not land on pr-<n>-pr-<n>.
[[ -n "$prefix" ]] || prefix="$(ticket_for "${pr_slug:-$(remote_slug . "$remote")}" "$pr")"
branch_slug="${branch//\//-}"
case "$branch_slug" in
	"$prefix" | "$prefix"-*) slug="$branch_slug" ;;
	*) slug="$prefix-$branch_slug" ;;
esac
dest="$worktree_root/$slug"

existing_wt="$(wt_for_branch "$branch")"
if [[ -n "$existing_wt" ]]; then
	# The PR's branch is already checked out — reuse that worktree wherever it is.
	dest="$existing_wt"
	echo "git pr: PR #$pr is already checked out at $dest — reusing" >&2
elif git worktree list --porcelain | grep -qxF "worktree $dest"; then
	# The destination is already a worktree (e.g. an earlier run) — reuse it.
	echo "git pr: reusing existing worktree at $dest" >&2
elif [[ -e "$dest" ]]; then
	echo "git pr: destination '$dest' exists and is not a worktree" >&2
	exit 1
else
	# Route git's progress chatter to stderr so stdout carries only the path.
	git fetch "$remote" "$pr_ref" >&2

	if git show-ref -q --verify "refs/heads/$branch"; then
		# Branch exists locally but isn't checked out anywhere — attach to it.
		git worktree add "$dest" "$branch" >&2
	else
		git worktree add -b "$branch" "$dest" "$pr_sha" >&2
	fi

	command -v zoxide >/dev/null 2>&1 && zoxide add "$dest" >/dev/null 2>&1 || true
fi

# Track the PR's branch on <remote>. Two things need this and neither works
# without it: `git push` from the worktree, and octo.nvim, whose use_local_fs
# only reads the working tree once in_pr_branch() recognises the checkout -
# which it decides from branch.<name>.merge, or from @{u}. Written directly
# rather than with --set-upstream-to, which insists on a remote-tracking ref:
# we fetched refs/pull/<n>/head, so refs/remotes/<remote>/<branch> need not
# exist. A fork PR keeps the pr/<n> fallback name and is left untracked, since
# <remote> does not carry that branch.
if [[ "$branch" != "pr/$pr" ]]; then
	git config "branch.$branch.remote" "$remote"
	git config "branch.$branch.merge" "refs/heads/$branch"
fi

# Name the session/editor workspace after <repo>/<slug>, matching the convention
# used by the `task` script.
session="$(basename "$worktree_root")/$slug"

# Create the session (idempotently) and, on first creation, launch a Claude
# PR-review prompt in it. Assumes a multiplexer is running (guarded by caller).
ensure_session() {
	mux_ensure_session "$session" "$dest"
	case $? in
		1)
			echo "git pr: reusing session $session" >&2
			return
			;;
		2)
			echo "git pr: could not create session $session" >&2
			return
			;;
	esac

	echo "git pr: created $(mux_backend) session $session" >&2

	if command -v claude >/dev/null 2>&1; then
		local main_branch prompt
		main_branch="$(git-main-branch 2>/dev/null || echo master)"
		# Single-quoted in the sent command line, so keep the prompt quote-free.
		prompt="Review pull request #${pr} (local branch ${branch}). Inspect the diff against ${main_branch} with git log and git diff to understand the change and its intent, then give your assessment: correctness, risks, and whether it looks ready to merge. Do not modify code yet."
		mux_send "$session" "claude '$prompt'"
	fi
}

open_in_emacs() {
	command -v emacsclient >/dev/null 2>&1 || {
		echo "git pr: emacsclient not found; skipping Emacs setup" >&2
		return
	}
	# Start the daemon on demand (1), create a Doom workspace + projectile
	# project for the worktree, and switch to it (1).
	wt_emacs_add "$slug" "$dest" 1 1 ||
		echo "git pr: failed to switch Emacs project to $dest" >&2
}

open_in_nvim() { wt_open_nvim "$session" "$dest"; }

open_in_zed() { wt_open_zed "$dest"; }

# Only orchestrate when stdout is a terminal. When captured in `$(...)`, stay a
# pure path emitter so `cd "$(git pr N)"` keeps working.
if [[ -t 1 ]]; then
	has_mux=0
	[[ "$(mux_backend)" != none ]] && has_mux=1

	# Create the session before the editor, so nvim can attach a window to it.
	[[ "$has_mux" -eq 1 ]] && ensure_session

	case "${GIT_PR_EDITOR:-emacs}" in
		emacs) open_in_emacs ;;
		nvim)
			if [[ "$has_mux" -eq 1 ]]; then
				open_in_nvim
			else
				echo "git pr: GIT_PR_EDITOR=nvim needs a multiplexer; skipping editor" >&2
			fi
			;;
		zed) open_in_zed ;;
		none) ;;
		*) echo "git pr: unknown GIT_PR_EDITOR '${GIT_PR_EDITOR}'" >&2 ;;
	esac

	# Switch last, so the client lands on the fully set-up session. Best-effort:
	# a failed switch shouldn't stop us from emitting the path below.
	[[ "$has_mux" -eq 1 ]] && { mux_switch "$session" || true; }
fi

echo "$dest"
