{
  inputs,
  config,
  pkgs,
  ...
}:

# TODO this module is basically a copy to the `zsh` one we need to trim down the duplication

{
  home.shellAliases = {
    l = "ls -lah";
    la = "ls -lAh";
    ll = "ls -l";
    ls = "ls --color=tty";
    lt = "ls -thalr";
    tux = "tmux -q has-session && exec tmux attach-session -d || exec tmux new-session -n$HOST";
    vim = "nvim";
  };

  programs.zsh = {
    enable = lib.mkDefault true;
    autocd = true;
    enableCompletion = true;
    dotDir = "${config.xdg.configHome}/zsh";
    defaultKeymap = "emacs";

    autosuggestion = {
      enable = lib.mkDefault true;
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
      ];
    };

    plugins = [
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
      plugins = [ ];
      theme = "robbyrussell";
      custom = "${config.programs.zsh.dotDir}/custom";
    };
  };

  # Have to deploy the file because if DOTFILES repo is not on target then customization won't work
  home.file.custom-robbyrussell = {
    enable = config.programs.zsh.oh-my-zsh.enable;
    source = ./custom/themes/robbyrussell.zsh-theme;
    target = "${config.programs.zsh.oh-my-zsh.custom}/themes/robbyrussell.zsh-theme";
  };
}
