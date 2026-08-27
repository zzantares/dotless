{
  inputs,
  profile,
  config,
  lib,
  pkgs,
  ...
}:

let
  # Shared, harness-agnostic agent knowledge (skills, rules, MCP), authored once in
  # ../agentic/knowledge.nix and consumed by every agent module.
  knowledge = import ../agentic/knowledge.nix { inherit pkgs inputs lib; };

  # Per-item live-override convention (mirrors wezterm/hyprland). For each item the
  # consumer lists in profile.liveOverrides.claude-code, symlink that item live
  # (out-of-store → editable, no rebuild) AND turn off dotless's baked version below,
  # so there's no double-owner collision on the path. Unlisted items keep the baked
  # default. Overriding an item fully REPLACES it (no merge with dotless's version).
  #
  # DECLARED, not detected: this used to probe the live tree with builtins.pathExists,
  # which is impure (needs --impure) and aborts eval in CI where the runner can't read
  # the user's home. TODO(dotless#48): replace this profile-level list with a
  # first-class, pure live-override mechanism shared across modules.
  #
  # NB: ~/.claude is a MIXED directory — config plus a lot of mutable runtime state
  # (history, sessions, projects, telemetry, …). Never symlink the whole dir; only the
  # individual config items listed by the consumer.
  claudeDir = "${config.home.homeDirectory}/${profile.flakeRoot}/config/claude";

  hasUserItem = rel: builtins.elem rel (profile.liveOverrides.claude-code or [ ]);

  liveItem =
    rel:
    lib.optionalAttrs (hasUserItem rel) {
      ".claude/${rel}".source = config.lib.file.mkOutOfStoreSymlink "${claudeDir}/${rel}";
    };
in
{
  programs.claude-code = {
    enable = lib.mkDefault (
      builtins.elem pkgs.stdenv.hostPlatform.system pkgs.claude-code.meta.platforms
    );
    package = lib.mkDefault pkgs.claude-code;

    # rules.<name> renders to ~/.claude/rules/<name>.md and applies to EVERY
    # project, unlike a repo's own CLAUDE.md which is only loaded inside that
    # repo. No `paths:` frontmatter, so these rules are global. Sourced from the
    # shared knowledge layer so Codex (and any rules-capable agent) gets the same set.
    rules = knowledge.rules;

    # Skills from the shared knowledge layer (../agentic), identical across agents.
    # Live-override branch: mkForce {} yields ~/.claude/skills to the consumer's
    # out-of-store symlink (one owner). Else mkDefault, so a consumer can override;
    # to ADD rather than replace, merge (knowledge.skills // { ... }).
    skills = if hasUserItem "skills" then lib.mkForce { } else lib.mkDefault knowledge.skills;

    # settings.json: if the consumer ships config/claude/settings.json, empty here so the
    # upstream module writes no settings.json, leaving the path free for the live symlink.
    settings =
      if hasUserItem "settings.json" then
        lib.mkForce { }
      else
        {
          autoUpdates = false;

          # Classic main-screen renderer, not the alt-screen "fullscreen" one.
          # Fullscreen virtualises its own scrollback, so the conversation never
          # reaches the terminal's history: tmux copy-mode sees one frozen frame
          # and the wheel is captured. Keep the transcript in real scrollback.
          tui = "default";

          env = {
            "DISABLE_AUTOUPDATER" = "1";

            # Attribute commits made by Claude Code (via its Bash tool, a child
            # process of this settings' own claude process) to Claude instead of
            # the human user — GIT_AUTHOR_*/GIT_COMMITTER_* env vars take
            # precedence over git's user.name/user.email config. Generic,
            # non-resolving defaults here since dotless is shared across
            # profiles; consumers override the email via mkDefault-eligible
            # plain definitions (e.g. dotfiles sets a real address tied to
            # their own Forgejo instance).
            "GIT_AUTHOR_NAME" = lib.mkDefault "Claude";
            "GIT_AUTHOR_EMAIL" = lib.mkDefault "claude@dotless";
            "GIT_COMMITTER_NAME" = lib.mkDefault "Claude";
            "GIT_COMMITTER_EMAIL" = lib.mkDefault "claude@dotless";
          };

          hooks = {
            # This is the hook that runs whenever a task is completed
            Stop = [
              {
                matcher = "";
                hooks = [
                  {
                    type = "command";
                    command = "~/.local/bin/claude-notify complete 'Claude - Task Completed'";
                  }
                ];
              }
            ];

            # This is the hook that runs whenever user input is requested
            Notification = [
              {
                matcher = "";
                hooks = [
                  # This will make Claude to issue a Tmux notification whenever it requires user attention
                  # In our configuration Tmux is configured to display it in the status bar when it gets issued
                  {
                    type = "command";
                    command = "tmux set-option @claude_attention 1";
                  }
                  {
                    type = "command";
                    command = "~/.local/bin/claude-notify message 'Claude - Needs Input'";
                  }
                ];
              }
            ];
          };
        };

    # Language servers for Claude Code's LSP tool, declared once for every
    # consumer instead of per-project from the marketplace. Store paths, not
    # bare names, so a server resolves without its toolchain in the profile.
    # Does not silence the install prompt; that is a ~/.claude.json key.
    lspServers = {
      typescript = {
        command = lib.getExe' pkgs.typescript-language-server "typescript-language-server";
        args = [ "--stdio" ];
        extensionToLanguage = {
          ".ts" = "typescript";
          ".tsx" = "typescriptreact";
          ".mts" = "typescript";
          ".cts" = "typescript";
          ".js" = "javascript";
          ".jsx" = "javascriptreact";
          ".mjs" = "javascript";
          ".cjs" = "javascript";
        };
      };

      rust-analyzer = {
        command = lib.getExe' pkgs.rust-analyzer "rust-analyzer";
        extensionToLanguage = {
          ".rs" = "rust";
        };
      };

      lua = {
        command = lib.getExe' pkgs.lua-language-server "lua-language-server";
        extensionToLanguage = {
          ".lua" = "lua";
        };
      };

      pyright = {
        command = lib.getExe' pkgs.pyright "pyright-langserver";
        args = [ "--stdio" ];
        extensionToLanguage = {
          ".py" = "python";
          ".pyi" = "python";
        };
      };
    };

    # See the HomeManager module docs for extra options they all look very interesting
    # settings = {}; # settings.json
    # agents = {};
    # agentsDir = ./;
    # hooksDir = ./;
    # skills = {};
    mcpServers = {
      forgejo = {
        type = "stdio";
        command = knowledge.forgejo.bin;
        args = knowledge.forgejo.args;
        # No env block: forgejo-mcp inherits FORGEJO_ACCESS_TOKEN from Claude's shell
        # env (exported by devstation secrets.nix). Same as the Codex module.
      };

      # github = {
      #   type = "remote";
      #   url = "https://api.githubcopilot.com/mcp/";
      #   headers = {
      #     Authorization = "Bearer {file:${config.sops.secrets.github_auth_token.path}}";
      #   };
      # };

      # memory = {
      #   command = [
      #     "podman"
      #     "run"
      #     "-i"
      #     "-v"
      #     "claude-memory:/app/dist"
      #     "--rm"
      #     "mcp/memory"
      #   ];
      #   type = "local";
      # };
    };
  };

  # Claude Code's Read tool renders PDF pages to images by shelling out to
  # `pdftoppm` (from poppler-utils); without it, reading a PDF fails with
  # "pdftoppm is not installed". Ship it here, next to where Claude Code is
  # enabled, so PDF reading works out of the box for every dotless consumer.
  home.packages = lib.optional config.programs.claude-code.enable pkgs.poppler-utils;

  # Declared items → live out-of-store symlinks (per-item; the wezterm / doom pattern).
  # Items the consumer does not list fall back to dotless's declarative defaults above
  # (or to nothing, for items dotless doesn't set).
  home.file = lib.mkMerge (map liveItem (profile.liveOverrides.claude-code or [ ]));

  # programs.mcp = {
  #   enable = true;

  #   servers = {
  #     github = {
  #       type = "remote";
  #       url = "https://api.githubcopilot.com/mcp/";
  #       headers = {
  #         Authorization = "Bearer {file:${config.sops.secrets.github_auth_token.path}}";
  #       };
  #     };

  #     memory = {
  #       command = [
  #         "podman"
  #         "run"
  #         "-i"
  #         "-v"
  #         "claude-memory:/app/dist"
  #         "--rm"
  #         "mcp/memory"
  #       ];
  #       type = "local";
  #     };

  #   };
  # };
}
