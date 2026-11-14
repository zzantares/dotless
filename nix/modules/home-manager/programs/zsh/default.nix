{
  profile,
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

{
  # Brings the `dotless.appearance` options this module sets.
  imports = [ ./../../appearance ];

  # Guarded: fzf exits 2 if this points at a file that is not there, and only
  # the switch hook creates it.
  home.sessionVariables = lib.mkIf config.dotless.appearance.enable {
    FZF_DEFAULT_OPTS_FILE = "${config.xdg.configHome}/fzf/colors-active";
  };

  xdg.configFile = {
    "fzf/colors-dark".text = "--color=dark,fg:white\n";
    # Solarized Light. bg stays -1 so the terminal shows through, as in dark.
    "fzf/colors-light".text =
      "--color=light,fg:#657b83,bg:-1,hl:#268bd2,fg+:#586e75,bg+:#eee8d5,hl+:#268bd2,"
      + "info:#93a1a1,prompt:#859900,pointer:#d33682,marker:#cb4b16,spinner:#2aa198,"
      + "border:#93a1a1,header:#93a1a1\n";
  };

  dotless.appearance.hooks = [
    ''
      install -m644 "${config.xdg.configHome}/fzf/colors-$mode" ${lib.escapeShellArg "${config.xdg.configHome}/fzf/colors-active"}
    ''
  ];

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
    vim = "nvim";
    e = "emacsclient -c -n";
    lazyvim = "NVIM_APPNAME=lazyvim nvim";
    q = "noglob claude --print --model haiku";
    cg = "cd $(git rev-parse --show-cdup)";
    hsfmt = "fd -e hs -X fourmolu --color always --check-idempotence --mode check";
    check = "cabal build --disable-optimization --ghc-options=\"+RTS -A256m -I0 -RTS -fno-code\"";
    recheck = "git diff --name-only | rg '\.hs$' | zz-hs-file-components | rg ':lib:' | xargs --no-run-if-empty cabal build --disable-optimization --ghc-options=\"+RTS -A256m -I0 -RTS -fno-code\"";
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    doom-reload = "doom sync && systemctl --user restart emacs.service";
  }
  // (profile.shellAliases or { });

  # Shared shell primitives for git-wt and git-pr. The directory ships as
  # one unit: that is how all.sh finds its siblings, here and from the store.
  home.file.shell-lib = {
    enable = lib.mkDefault true;
    source = ./lib;
    target = "${config.home.homeDirectory}/.local/lib/sh";
  };

  programs.zsh = {
    enable = lib.mkDefault true;
    autocd = lib.mkDefault true;
    enableCompletion = lib.mkDefault true;
    dotDir = "${config.xdg.configHome}/zsh";
    defaultKeymap = "emacs";

    autosuggestion = {
      enable = lib.mkDefault true;
      highlight = "fg=102";
      strategy = [ "history" ];
    };

    history = {
      share = lib.mkDefault true;
      append = lib.mkDefault true;
      ignoreDups = lib.mkDefault true;
      ignoreSpace = lib.mkDefault true;
      ignoreAllDups = lib.mkDefault true;
      expireDuplicatesFirst = lib.mkDefault true;
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
      enable = lib.mkDefault true;
      highlighters = [
        "main"
        "brackets"
        "pattern"
      ];
    };

    oh-my-zsh = {
      enable = lib.mkDefault true;
      plugins = [
        "direnv"
        "fzf"
      ];
      theme = profile.ohMyZshTheme;
      custom = "${./custom}";
    };

    # A re-login leaks HM's own guard into the session env, so hm-session-vars
    # self-skips and /etc/set-environment's EDITOR, PAGER and PATH win.
    # Re-apply in every zsh; typeset -U keeps the prepend idempotent.
    envExtra = ''
      unset __HM_SESS_VARS_SOURCED
      source ${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh
      typeset -U path
    '';

    initContent = lib.mkMerge [
      (lib.mkBefore (
        ''
          # source the nix profiles outside of TMUX (to avoid re-sourcing)
          if [[ -z "$TMUX" && -r "${config.home.homeDirectory}/.nix-profile/etc/profile.d/nix.sh" ]]; then
            source "${config.home.homeDirectory}/.nix-profile/etc/profile.d/nix.sh"
          fi

          # Creates a menu for tmux-fzf that exposes Claude Code sessions (defined in overlays)
          export TMUX_FZF_MENU="Claude Sessions\n${pkgs.tmux-claude-picker}/bin/tmux-claude-picker\n"
        ''
        + lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
          # Workaround for: https://github.com/Mic92/sops-nix/issues/687
          ${pkgs.systemd}/bin/systemctl --user start sops-nix-starter.service
        ''
      ))
      (lib.mkAfter (lib.readFile ./extra.zsh))
    ];
  };

  programs.direnv = {
    enable = lib.mkDefault true;
    silent = lib.mkDefault false;
    enableZshIntegration = lib.mkDefault true;
    nix-direnv.enable = lib.mkDefault true;
    nix-direnv.package = pkgs.nix-direnv;
  };

  programs.zoxide = {
    enable = lib.mkDefault true;
    enableZshIntegration = lib.mkDefault true;
  };

  programs.fzf = {
    enable = lib.mkDefault true;
    enableZshIntegration = lib.mkDefault true;

    tmux = {
      # NOTE this is enabled conditionally in `./extra.zsh` due to emacs-vterm
      #   which won't play nice with it when triggered within Emacs
      enableShellIntegration = lib.mkDefault false;
      shellIntegrationOptions = [ "-p" ];
    };

    defaultCommand = "fd . --hidden --exclude .git";
    defaultOptions = [
      "--pointer='→'"
      "--layout=reverse"
      "--bind ctrl-k:down,ctrl-h:up"
      "--bind '?:toggle-preview'"
      "--border=rounded"
    ];

    # Triggered by Ctrl + r
    historyWidget.options = [
      "--no-sort"
      "--no-preview"
      "--height=40%"
      "--layout=reverse"
      "--border-label='History '"
      "--with-nth 2.."
    ];

    # Triggered by Ctrl + f
    fileWidget.options = [
      "--select-1"
      "--exit-0"
      "--border-label='Files '"
      "--preview 'bat --style=numbers,changes --show-all --wrap=never --color=always --line-range=:500 {} || cat {} || tree -C {}'"
    ];

    # Triggered by Alt + c
    changeDirWidget.options = [
      "--preview 'tree -C {} | head -200'"
      "--border-label='Directories '"
    ];

  };
}
