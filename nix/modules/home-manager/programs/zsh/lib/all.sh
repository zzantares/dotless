# shellcheck shell=bash
#
# Every module in this directory, for scripts that want the lot:
#
#   source "$HOME/.local/lib/sh/all.sh"
#
# A script that needs one module sources that module instead - boom takes
# emacs.sh only. Each module guards itself, so sourcing this file and a
# module in the same process is safe.
#
# Modules are listed one per line rather than globbed: a glob makes load order
# alphabetical accident, and a stray file in the directory becomes code.

[[ -n "${_DOTLESS_ALL_SH:-}" ]] && return 0
_DOTLESS_ALL_SH=1

# Resolve siblings through this file's own path, so the same line works from
# ~/.local/lib/sh and from the Nix store, where the whole directory is one
# store path.
_dotless_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./emacs.sh
source "$_dotless_lib_dir/emacs.sh"
# shellcheck source=./worktree.sh
source "$_dotless_lib_dir/worktree.sh"

unset _dotless_lib_dir
