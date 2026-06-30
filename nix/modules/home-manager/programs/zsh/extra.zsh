
# Do not append "not found command" to history
# see: https://superuser.com/a/902508/897543
zshaddhistory() {
    local j=1
    # skip words while they look like environment var assignments
    while ([[ ${${(z)1}[$j]} == *=* ]]) {
        ((j++))
    }
    whence ${${(z)1}[$j]} >| /dev/null || return 2
}

# Add hook to remove last command from history if it failed
# see: https://unix.stackexchange.com/a/790022/462151
# TODO needs fine tunning so failing tests don't cause the test command to be erased from history
# delete-failed-history() {
#     case $? in
#     0|130|137)
#       ;; # Do nothing for allowed codes like ctrl+c (e.g. SIGINT)
#     *)
#       hist -s d -1  # from Marlon Richert's zsh-hist plugin
#       ;;
#   esac
# }
# autoload -Uz add-zsh-hook
# add-zsh-hook precmd delete-failed-history

# I don't want fzf-tmux in emacs-vterm until I figure how to integrate these better
if [[ -z "$INSIDE_EMACS" ]]; then
    enable-fzf-tab
    export FZF_TMUX=1
fi

# Reconfigure batman as the MANPAGER
eval "$(batpipe)"
eval "$(batman --export-env)"

[[ -f "${HOME}/.ghcup/env" ]] && source "${HOME}/.ghcup/env" # ghcup-env


# Change C-t file widget to C-f for fzf
# TODO there's already a C-f binding for fzf that's getting overriden by this
bindkey -r '^T'
bindkey '^F' fzf-file-widget
bindkey '^L' clear-screen

# Provide pbcopy/pbpaste on systems that lack them (Linux/WSL). macOS ships
# both natively, so guard the definitions to avoid shadowing the real commands.
if ! command -v pbcopy >/dev/null 2>&1; then
    pbcopy() {
        if [[ -n "$WSL_DISTRO_NAME" ]]; then
            clip.exe "$@"
        else
            xclip -selection clipboard "$@"
        fi
    }
fi

if ! command -v pbpaste >/dev/null 2>&1; then
    pbpaste() {
        if [[ -n "$WSL_DISTRO_NAME" ]]; then
            powershell.exe Get-Clipboard
        else
            xclip -selection clipboard -o "$@"
        fi
    }
fi

# NOTE we need to keep this one lean and fast because it's usually triggered in a pre-commit
glint () {
    # TODO Check the function is called in a git repository
    touched_files="$(git diff --name-only --cached)"

    if [[ "$touched_files" == "" ]]; then
        return 0
    fi

    rg '\.hs$' <<< "$touched_files" | xargs --no-run-if-empty --verbose hlint -q --color=never
    rg '\.hs$' <<< "$touched_files" | xargs --no-run-if-empty --verbose fourmolu -m check --color=never -c
    rg '\.sh$' <<< "$touched_files" | xargs --no-run-if-empty --verbose shellcheck
    rg '\.sql$' <<< "$touched_files" | xargs --no-run-if-empty --verbose sqlfluff lint -n
}

fzf-git-branch() {
    git rev-parse HEAD > /dev/null 2>&1 || return # check we're on a repo

    git branch --color=always --all --sort=-committerdate \
        | rg -v HEAD \
        | fzf \
            --height 50% \
            --ansi \
            --no-multi \
            --preview-window right:65% \
            --preview 'git log -n 50 --color=always --date=short --pretty="format:%C(auto)%cd %h%d %s" $(sed "s/.* //" <<< {})' \
        | sed "s/.* //"
}

fzf-git-checkout() {
    git rev-parse HEAD > /dev/null 2>&1 || return # check we're on a repo

    local branch="$(fzf-git-branch)"
    [[ -z "$branch" ]] && return # No branch selected

    # If branch name starts with 'remotes/' then it is a remote branch. By
    # using --track and a remote branch name, it is the same as:
    # git checkout -b branchName --track origin/branchName
    if [[ "$branch" =~ ^remotes/ ]]; then
        git checkout --track $branch
    else
        git checkout $branch
    fi
}

# Remove all merged branches
git-rm-merged() {
    git branch --no-color --merged \
        | rg -v "^([+*]|\s*($(git-main-branch)|$(git_develop_branch))\s*$)" \
        | xargs git branch --delete 2>/dev/null
}

# Remove all squashed branches
# Copied and modified from James Roeder (jmaroeder) under MIT License
# https://github.com/jmaroeder/plugin-git/blob/216723ef4f9e8dde399661c39c80bdf73f4076c4/functions/gbda.fish
git-rm-squashed() {
  local default_branch="$(git-main-branch)"

  git for-each-ref refs/heads/ "--format=%(refname:short)" \
    | while read branch; do
        local merge_base="$(git merge-base ${default_branch} ${branch})"
        if [[ $(git cherry "$default_branch" $(git commit-tree $(git rev-parse "$branch"\^{tree}) -p "$merge_base" -m _)) = -* ]]; then
            git branch -D "$branch"
        fi
      done
}

cabalb () {
    cabal build --enable-tests --enable-benchmarks "$@"
    cabal haddock --haddock-for-hackage "$@"
}

# graphite-cli shell completion
#compdef gt
###-begin-gt-completions-###
#
# yargs command completion script
#
# Installation: gt completion >> ~/.zshrc
#    or gt completion >> ~/.zprofile on OSX.
#
_gt_yargs_completions()
{
  local reply
  local si=$IFS
  IFS=$'
' reply=($(COMP_CWORD="$((CURRENT-1))" COMP_LINE="$BUFFER" COMP_POINT="$CURSOR" gt --get-yargs-completions "${words[@]}"))
  IFS=$si
  _describe 'values' reply
}
compdef _gt_yargs_completions gt
###-end-gt-completions-###

