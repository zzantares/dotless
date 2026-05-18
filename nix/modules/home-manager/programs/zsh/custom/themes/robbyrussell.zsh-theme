PROMPT='%(?:%{$fg_bold[green]%}%1{➜%} :%{$fg_bold[red]%}%1{➜%} ) $([[ -n $SSH_CONNECTION ]] && print -r -- "%{$reset_color%}%B$USER%{$fg_bold[yellow]%}@%M%{$reset_color%}%b ")%{$fg[cyan]%}$([[ -n $SSH_CONNECTION ]] && print -r -- "%~" || print -r -- "%c")%{$reset_color%}'

PROMPT+=' $(git_prompt_info)'

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}git:(%{$fg[red]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%} "
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[yellow]%}%1{✗%}"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%})"
