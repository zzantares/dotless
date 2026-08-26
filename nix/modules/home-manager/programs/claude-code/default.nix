{
  inputs,
  profile,
  config,
  lib,
  pkgs,
  ...
}:

let
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
    # repo. No `paths:` frontmatter, so this rule is global.
    rules.comments = ''
      # Comment Discipline

      Hard limits on every in-code comment you write or edit. Not style
      suggestions - constraints.

      1. Length cap. A comment must never exceed 280 characters (one tweet),
         counting the whole comment across all its lines. Aim well under that.

      2. Never grow a comment. When you rephrase, update, or fix an existing
         comment, the result must be the same length or shorter than what was
         there before - never longer. Shortening is always fine; lengthening
         is not.

      3. Exceptions need approval. If a comment genuinely cannot satisfy rule 1
         or 2 and there is truly no alternative, do not write it. Ask the user
         for explicit approval first, with your best justification for why the
         exception is necessary. Only proceed if they approve.
    '';

    # Global (no `paths:`): every project. Nudges Claude toward blunt, concise
    # answers instead of long-winded prose.
    rules.brevity = ''
      # Answer Style: Brevity

      Default to short, direct answers. Lead with the answer, then only the
      detail that earns its place. Blunt beats polished.

      - Cut preamble, filler, and hedging. Don't restate the question, don't
        open with "great question", don't preface the answer by previewing it
        ("here's what I'll cover..."). Just say it.
      - Prefer fragments and lists over prose paragraphs.
      - Match length to the task. A simple question gets a line or two, not a
        paragraph. Don't pad with options or caveats the user didn't ask for;
        one clear recommendation beats a survey.

      Brevity means cutting filler, not substance. Keep the facts, numbers, and
      caveats that change what the user does - just drop the words around them.
    '';

    # Global (no `paths:`): every project. Mechanical writing conventions,
    # separate from rules.brevity (which governs length, not punctuation or
    # word choice).
    rules.writing-mechanics = ''
      # Writing Mechanics

      Applies to every bit of text you produce - chat, commit messages, PR
      titles and bodies, docs, code comments.

      1. Hyphens only. Use a plain hyphen (`-`), never an em-dash (`—`) or
         en-dash (`–`). They render inconsistently across fonts and read as AI
         boilerplate.

      2. Domain words, not filler metaphors. Drop vague, over-used terms that
         add no meaning - e.g. "seam", "load-bearing", "delve", "robust",
         "leverage". Pick the precise word for the domain at hand.
    '';

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
