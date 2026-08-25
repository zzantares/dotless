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
    ./../../../modules/home-manager/programs/wezterm
    ./../../../modules/home-manager/programs/emacs
    ./../../../modules/home-manager/programs/fourmolu
    ./../../../modules/home-manager/programs/claude-code
    ./../../../modules/home-manager/programs/opencode
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

  programs.gh-dash.enable = true;
  programs.gh-dash.settings = {
    # Render the `d` diff view through diffnav: a GitHub-style pager with a file
    # tree for navigating large PRs per-file/per-directory. diffnav renders the diff
    # through delta under the hood, so `[delta]` git config styling still applies.
    # (Its keybindings are patched to Colemak via nix/overlays/private.nix, matching
    # the universal keys below.) Swap back to `delta` for a plain scrolling diff.
    pager.diff = "diffnav";

    # Colemak-flavored navigation (cf. the aerospace workspace bindings):
    #   h = up, k = down, j = left (prev section), l = right (next section).
    # gh-dash rebinds a builtin by *replacing* its key list, so these four form a
    # clean permutation of the defaults. Trade-off: only one key per builtin is
    # settable, so the arrow-key fallback for these actions is dropped.
    keybindings.universal = [
      {
        key = "h";
        builtin = "up";
      }
      {
        key = "k";
        builtin = "down";
      }
      {
        key = "j";
        builtin = "prevSection";
      }
      {
        key = "l";
        builtin = "nextSection";
      }
    ];

    # PR-only bindings that drive src/bin/pr-brief (Phase 1 of the review flow):
    #   b — generate/refresh the briefing for the highlighted PR into the local
    #       inbox (idempotent: skips if the PR is unchanged since last brief), then
    #       show it in a pager. gh-dash runs these via tea.ExecProcess, which hands
    #       pr-brief the real terminal, so the pager takes over the screen — quit
    #       it (q) to drop back to the dashboard.
    #   B — same, then open the briefing file in the editor (-o) instead of paging.
    # gh-dash runs these with the row's template vars; {{.RepoName}} is owner/repo
    # and {{.PrNumber}} is the PR number, which pr-brief accepts as owner/repo#123.
    prs = [
      {
        key = "b";
        name = "brief PR";
        command = "pr-brief {{.RepoName}}#{{.PrNumber}}";
      }
      {
        key = "B";
        name = "brief + open";
        command = "pr-brief -o {{.RepoName}}#{{.PrNumber}}";
      }
    ];

    # Starter sections (mirror gh-dash's own defaults); edit to taste.
    prSections = [
      {
        title = "My Pull Requests";
        filters = "is:open author:@me";
      }
      {
        title = "Needs My Review";
        filters = "is:open review-requested:@me";
      }
      {
        title = "Involved";
        filters = "is:open involves:@me -author:@me";
      }
    ];

    issuesSections = [
      {
        title = "My Issues";
        filters = "is:open author:@me";
      }
      {
        title = "Assigned";
        filters = "is:open assignee:@me";
      }
      {
        title = "Involved";
        filters = "is:open involves:@me -author:@me";
      }
    ];
  };

  # A systemd service to update tldr cache
  systemd.user.services.tldr-cache-update = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
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
  systemd.user.timers.tldr-cache-update = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
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
    grabKeyboardAndMouse = lib.mkIf pkgs.stdenv.hostPlatform.isLinux true;
    pinentry.package = lib.mkDefault (
      if pkgs.stdenv.hostPlatform.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-curses
    );
  };

  programs.zellij = {
    enable = true;
    enableZshIntegration = false; # see: https://github.com/zellij-org/zellij/discussions/1721
    settings = {
      simplified_ui = true;
      default_shell = "${config.programs.zsh.package}/bin/zsh";
      mouse_mode = false;
      scroll_buffer_size = 10000;
      copy_command = lib.mkIf pkgs.stdenv.hostPlatform.isLinux "xclip -selection clipboard";

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

  systemd.user.services.hoogle = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
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

  systemd.user.timers.hoogle = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
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
  systemd.user.services.sops-nix-starter = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
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
