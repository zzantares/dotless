{
  profile,
  pkgs,
  lib,
  config,
  ...
}:

{
  imports = [
    ./../base
    ./../../../modules/home-manager/dotfiles
    ./../../../modules/home-manager/programs/git
    ./../../../modules/home-manager/programs/tmux
    ./../../../modules/home-manager/programs/zsh
    ./../../../modules/home-manager/programs/bat
    ./../../../modules/home-manager/email
    ./../../../modules/home-manager/programs/alacritty
    ./../../../modules/home-manager/programs/emacs
    ./../../../modules/home-manager/programs/fourmolu
    ./../../../modules/home-manager/programs/claude-code
    ./clojure.nix
    ./packages.nix
    ./secrets.nix
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      serif = [
        "Noto Serif"
        "DejaVu Serif"
      ];

      sansSerif = [
        "Overpass, Light"
        "Ubuntu Sans, Light"
        "Overpass"
        "Ubuntu Sans"
        "Ubuntu"
      ];

      monospace = [
        "JetBrains Mono"
        "Overpass Mono"
        "Cascadia Code"
        "Inconsolata, Regular"
        "Ubuntu Mono"
      ];
    };
  };

  home.sessionPath = [
    "${config.xdg.configHome}/emacs/bin"
    "${config.home.homeDirectory}/.cargo/bin"
    "${config.home.homeDirectory}/.local/bin"
  ];

  home.sessionVariables = {
    DOTFILES_FLAKE_ROOT = lib.mkDefault "${config.home.homeDirectory}/${profile.flakeRoot}";
    ASPELL_CONF = lib.mkDefault "data-dir ${pkgs.aspell-with-dicts}/lib/aspell";

    # Improves Ansible interaction
    ANSIBLE_FORCE_COLOR = lib.mkDefault "True";
    ANSIBLE_STDOUT_CALLBACK = lib.mkDefault "yaml";
    ANSIBLE_SSH_ARGS = lib.mkDefault "-o ControlMaster=auto -o ControlPersist=60s -F ${config.home.homeDirectory}/.ssh/config";
    ANSIBLE_REMOTE_USER = lib.mkDefault config.home.username;

    # Speed up Emacs LSP: https://emacs-lsp.github.io/lsp-mode/page/performance/#use-plists-for-deserialization
    LSP_USE_PLISTS = lib.mkDefault "true";

    # Used by qwen-code
    OPENAI_BASE_URL = lib.mkDefault "https://openrouter.ai/api/v1";
    OPENAI_MODEL = lib.mkDefault "qwen/qwen3-coder:free";
  };

  home.shellAliases = { } // (profile.shellAliases or { });

  # A systemd service to update tldr cache
  systemd.user.services.tldr-cache-update = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Update tldr cache.";
      After = [ "network.target" ];
    };

    Service = {
      # Skip the update if the cache was refreshed within the last day
      ExecCondition = pkgs.writeShellScript "tldr-cache-age-check" ''
        cache_dir="${config.xdg.cacheHome}/tealdeer"
        if [[ -d "$cache_dir" ]] && [[ -z "$(find "$cache_dir" -maxdepth 0 -mmin +1440)" ]]; then
          exit 1
        fi
      '';
      ExecStart = "${pkgs.tealdeer}/bin/tldr --update";
      Type = "oneshot";
      TimeoutStartSec = 10;
    };

    Install.WantedBy = [ "default.target" ];
  };

  # A systemd timer to constantly trigger the service that updates the tldr cache
  systemd.user.timers.tldr-cache-update = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Keep tldr cache fresh.";
    Timer.OnCalendar = "12:30";
    Install.WantedBy = [ "timers.target" ];
  };

  programs.gpg.enable = true;

  services.gpg-agent = {
    enable = true;
    maxCacheTtl = 14400;
    defaultCacheTtl = 1200;
    enableZshIntegration = true;
    grabKeyboardAndMouse = lib.mkIf pkgs.stdenv.isLinux true;
    pinentry.package = if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-curses;
  };

  programs.zellij = {
    enable = true;
    enableZshIntegration = false; # see: https://github.com/zellij-org/zellij/discussions/1721
    settings = {
      simplified_ui = true;
      default_shell = "${config.programs.zsh.package}/bin/zsh";
      mouse_mode = false;
      scroll_buffer_size = 10000;
      copy_command = lib.mkIf pkgs.stdenv.isLinux "xclip -selection clipboard";

      # pane_frames = true;
      theme = "one-half-dark";
      default_layout = "compact";
    };
  };

  programs.pgcli = {
    # TODO apparently after an update the package is broken but since we don't use it much can be disabled
    enable = false;
    settings = {
      main = {
        timing = true;
        multi_line = true;
        generate_aliases = true;
        smart_completion = true;
        use_local_timezone = false;
        destructive_warning = true;
        destructive_statements_require_transaction = true;
        log_file = "${config.xdg.cacheHome}/pgcli/log";
        casing_file = "${config.xdg.cacheHome}/pgcli/casing";
        history_file = "${config.xdg.cacheHome}/pgcli/history";
      };
    };
  };

  systemd.user.services.hoogle = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Start a local Hoggle server.";
      After = [ "network.target" ];
    };

    Service = {
      Type = "simple";
      Restart = "always";
      WorkingDirectory = "/tmp";
      ExecStart = "${pkgs.toolchains.haskell}/bin/hoogle server --port 8123 --local --haskell";
      StandardOutput = "journal";
      StandardError = "journal";
    };

    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.timers.hoogle = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Keep Hoogle database up to date.";
    Timer.OnCalendar = "weekly";
  };

  # We put this here because it only makes sense on devstations
  programs.opencode.settings = {
    lsp = {
      hls = {
        command = [
          "haskell-language-server-wrapper"
          "--lsp"
        ];
        extensions = [
          ".hs"
        ];
      };
    };
  };

  # Workaround for: https://github.com/Mic92/sops-nix/issues/687
  systemd.user.services.sops-nix-starter = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Trigger sops-nix after login (decryption at startup workaround)";
      After = [ "default.target" ];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = "${pkgs.systemd}/bin/systemctl --user start sops-nix.service";
    };

    Install.WantedBy = [ "default.target" ];
  };
}
