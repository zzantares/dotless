{
  profile,
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

{
  home.shellAliases = {
    gs = "git status";
    gis = "command gs"; # git-spice was renamed to `gs` but I want `gs` to mean status
    gco = "fzf-git-checkout";
    gbr = "fzf-git-branch";
    # TODO switch to eza or lsd?
    l = "ls -lah";
    la = "ls -lAh";
    ll = "ls -l";
    ls = "ls --color=tty";
    lt = "ls -thalr";
    tux = "tmux -q has-session && exec tmux attach-session -d || exec tmux new-session -n$HOST";
    vim = "nvim";
    e = "emacsclient -c -n";
    lazyvim = "NVIM_APPNAME=lazyvim nvim";
    q = "noglob claude --print --model haiku";
    cg = "cd $(git rev-parse --show-cdup)";
    hsfmt = "fd -e hs -X fourmolu --color always --check-idempotence --mode check";
    check = "cabal build --disable-optimization --ghc-options=\"+RTS -A256m -I0 -RTS -fno-code\"";
    recheck = "git diff --name-only | rg '\.hs$' | zz-hs-file-components | rg ':lib:' | xargs --no-run-if-empty cabal build --disable-optimization --ghc-options=\"+RTS -A256m -I0 -RTS -fno-code\"";
    dev = "ghcid --command \"cabal repl $@\"";
    doom-reload = "doom sync && systemctl --user restart emacs.service";
  }
  // (profile.shellAliases or {});

  programs.zsh = {
    enable = true;
    autocd = true;
    enableCompletion = true;
    dotDir = "${config.xdg.configHome}/zsh";
    defaultKeymap = "emacs";

    autosuggestion = {
      enable = true;
      highlight = "fg=102";
      strategy = [ "history" ];
    };

    history = {
      share = true;
      append = true;
      ignoreDups = true;
      ignoreSpace = true;
      ignoreAllDups = true;
      expireDuplicatesFirst = true;
      save = 100000;
      size = builtins.ceil (config.programs.zsh.history.save * 1.2); # $HISTSIZE should be at least 20% larger than $SAVEHIST
      ignorePatterns = [
        "rm *"
        "pkill *"
        "kill *"
        "q *"
      ];
    };

    dirHashes = {
      docs = "$HOME/Documents";
    };

    plugins = [
      {
        name = "fzf-tab"; # pname will resolve to "zsh-fzf-tab" which is wrong so we don't use it here
        src = pkgs.zsh-fzf-tab.src;
      }
      {
        name = "zsh-hist";
        src = inputs.zsh-hist;
      }
      # TODO Shouldn't be necessary if `programs.zsh.enableCompletion` is set but somehow didn't work
      {
        name = pkgs.zsh-completions.pname;
        src = pkgs.zsh-completions.src;
      }
      # TODO Shouldn't be necessary if `programs.zsh.enableCompletion` is set but somehow didn't work
      {
        name = pkgs.nix-zsh-completions.pname;
        src = pkgs.nix-zsh-completions.src;
      }
    ];

    syntaxHighlighting = {
      enable = true;
      highlighters = [
        "main"
        "brackets"
        "pattern"
      ];
    };

    oh-my-zsh = {
      enable = true;
      plugins = [
        "direnv"
        "fzf"
      ];
      theme = profile.ohMyZshTheme;
      custom = builtins.toString ./custom;
    };

    initContent = lib.mkMerge [
      (lib.mkBefore ''
        # source the nix profiles outside of TMUX (to avoid re-sourcing)
        if [[ -z "$TMUX" && -r "${config.home.homeDirectory}/.nix-profile/etc/profile.d/nix.sh" ]]; then
          source "${config.home.homeDirectory}/.nix-profile/etc/profile.d/nix.sh"
        fi

        # Creates a menu for tmux-fzf that exposes Claude Code sessions (defined in overlays)
        export TMUX_FZF_MENU="Claude Sessions\n${pkgs.tmux-claude-picker}/bin/tmux-claude-picker\n"

        # Workaround for: https://github.com/Mic92/sops-nix/issues/687
        ${pkgs.systemd}/bin/systemctl --user start sops-nix-starter.service
      '')
      (lib.mkAfter (lib.readFile ./extra.zsh))
    ];
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    nix-direnv.package = pkgs.nix-direnv;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;

    tmux = {
      # NOTE this is enabled conditionally in `./extra.zsh` due to emacs-vterm
      #   which won't play nice with it when triggered within Emacs
      enableShellIntegration = false;
      shellIntegrationOptions = [ "-p" ];
    };

    defaultCommand = "fd . --hidden --exclude .git";
    defaultOptions = [
      "--pointer='→'"
      "--color='dark,fg:white'"
      "--layout=reverse"
      "--bind ctrl-k:down,ctrl-h:up"
      "--bind '?:toggle-preview'"
      "--border=rounded"
    ];

    # Triggered by Ctrl + r
    historyWidgetOptions = [
      "--no-sort"
      "--no-preview"
      "--height=40%"
      "--layout=reverse"
      "--border-label='History '"
      "--with-nth 2.."
    ];

    # Triggered by Ctrl + f
    fileWidgetOptions = [
      "--select-1"
      "--exit-0"
      "--border-label='Files '"
      "--preview 'bat --style=numbers,changes --show-all --wrap=never --color=always --line-range=:500 {} || cat {} || tree -C {}'"
    ];

    # Triggered by Alt + c
    changeDirWidgetOptions = [
      "--preview 'tree -C {} | head -200'"
      "--border-label='Directories '"
    ];

  };
}
