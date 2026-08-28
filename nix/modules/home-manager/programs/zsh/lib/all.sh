# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# Every module in this directory, for scripts that want the lot:
#
#   source "$HOME/.local/lib/sh/all.sh"
#
# Listed one per line, not globbed: a glob makes load order alphabetical
# accident and turns a stray file into code.

[[ -n "${_DOTLESS_ALL_SH:-}" ]] && return 0
_DOTLESS_ALL_SH=1

# Resolve siblings by this file's own path: works from ~/.local/lib/sh and from
# the store, where the directory is one path.
_dotless_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=emacs.sh
source "$_dotless_lib_dir/emacs.sh"
# shellcheck source=worktree.sh
source "$_dotless_lib_dir/worktree.sh"

unset _dotless_lib_dir
