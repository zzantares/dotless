{
  inputs,
  profile,
  config,
  lib,
  pkgs,
  ...
}:

let
  # Per-item live-override convention (mirrors the wezterm module). For each known
  # Claude config item, if the consumer ships it under their flake's config/claude/,
  # symlink that item live (out-of-store → editable, no rebuild) AND turn off dotless's
  # declarative version of it below, so there's no double-owner collision on the path.
  # Anything the consumer doesn't provide keeps dotless's baked-in default.
  #
  # Detection keys on each ITEM's own path (not the bare config/claude dir), so items
  # can be overridden piecemeal and a stray empty dir can't silently wipe the defaults
  # (same rationale as the wezterm module's wezterm.lua entrypoint check). Overriding an
  # item fully REPLACES it — there is no merge with dotless's version (matches wezterm).
  #
  # NB: ~/.claude is a MIXED directory — config plus a lot of mutable runtime state
  # (history, sessions, projects, telemetry, …). Never symlink the whole dir; only the
  # individual config items enumerated here. Evaluated at switch time under --impure.
  claudeDir = "${config.home.homeDirectory}/${profile.flakeRoot}/config/claude";

  overridableItems = [
    "settings.json"
    "skills"
    "agents"
    "commands"
    "rules"
    "hooks"
    "CLAUDE.md"
    "output-styles"
  ];

  hasUserItem = rel: builtins.pathExists "${claudeDir}/${rel}";

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
    # skills: if the consumer ships config/claude/skills/, the live symlink (see the
    # home.file block below) owns ~/.claude/skills; empty here so the upstream module
    # writes nothing for that path and there is no double-owner collision.
    #
    # Attrset form (not the bare ./skills path) so dotless's own baked skills coexist
    # with skills sourced from external flake inputs. Each subdir of ./skills is one
    # skill; simple-english comes from the pinned SimpleEnglish input (ASD-STE100
    # Simplified Technical English), its skills/simple-english/ dir carrying SKILL.md
    # plus references/.
    skills =
      if hasUserItem "skills" then
        lib.mkForce { }
      else
        {
          changelog = ./skills/changelog;
          explain = ./skills/explain;
          simple-english = "${inputs.simple-english}/skills/simple-english";
        };

    # settings.json: if the consumer ships config/claude/settings.json, empty here so the
    # upstream module writes no settings.json, leaving the path free for the live symlink.
    settings =
      if hasUserItem "settings.json" then
        lib.mkForce { }
      else
        {
          autoUpdates = false;
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

    # See the HomeManager module docs for extra options they all look very interesting
    # settings = {}; # settings.json
    # agents = {};
    # agentsDir = ./;
    # hooksDir = ./;
    # skills = {};
    mcpServers = {
      forgejo = {
        type = "stdio";
        command = "${pkgs.forgejo-mcp}/bin/forgejo-mcp";
        args = [
          "--transport"
          "stdio"
          "--url"
          "https://git.gutimore.net"
        ];
        env = {
          FORGEJO_ACCESS_TOKEN = "\${FORGEJO_ACCESS_TOKEN}";
        };
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

  # Consumer-provided config items → live out-of-store symlinks (per-item; the wezterm /
  # doom pattern). Items the consumer doesn't ship fall back to dotless's declarative
  # defaults above (or to nothing, for items dotless doesn't set). liveItem yields {} for
  # absent items, so this merges down to only the paths the consumer actually provides.
  home.file = lib.mkMerge (map liveItem overridableItems);

  programs.opencode = {
    enable = lib.mkDefault true;
    package = pkgs.opencode;
    enableMcpIntegration = true;
    settings = {
      autoupdate = false;
      instructions = [ "CLAUDE.md" ]; # Compatibility with claude-code
      model = "anthropic/claude-opus-4-5";
      # github-agent = {
      #   description = "Handles github.com tasks";
      #   mode = "subagent";
      #   tools = {
      #     "github*" = true;
      #   };
      # };
    };
    # themes = {};
    # agents = {};
    # commands = {};
    # rules = {};
  };

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
