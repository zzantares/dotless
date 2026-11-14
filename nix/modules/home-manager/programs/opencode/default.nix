{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

let
  # Shared agent knowledge - the same SKILL.md dirs and global rules Claude Code
  # uses. See ../agentic/knowledge.nix.
  knowledge = import ../agentic/knowledge.nix { inherit pkgs inputs lib; };
in
{
  # Brings the `dotless.appearance` options this module sets.
  imports = [ ./../../appearance ];

  programs.opencode = {
    enable = lib.mkDefault true;
    package = pkgs.opencode;
    enableMcpIntegration = true;

    # Skills shared verbatim with Claude Code / Codex (opencode reads the same
    # SKILL.md format) -> ~/.config/opencode/skills/<name>/.
    skills = knowledge.skills;

    # opencode has no rules mechanism, so the shared preamble + global rule bodies
    # ride in `context`, rendered to ~/.config/opencode/AGENTS.md.
    context = knowledge.agentsMd;

    # Keybinds and theme live in tui.json, not opencode.json: opencode strips
    # `theme`/`keybinds`/`tui` out of `settings` and migrates them, which fails
    # against a read-only store symlink. See `programs.opencode.tui`.
    tui = {
      theme = "nord"; # Matches doom's nordic-night.
      leader_timeout = 3000;

      # Built-in which-key panel, shipped disabled upstream. Doom-style leader
      # discoverability; ctrl+alt+k toggles the panel.
      plugin_enabled."which-key" = true;

      # OSC desktop notification + sound when a run needs input or finishes.
      attention = {
        enabled = true;
        notifications = true;
        sound = true;
      };

      keybinds = {
        # Dead keys in this terminal stack: wezterm's leader is ctrl+t, tmux's
        # prefix is C-b with prefix2 C-t, so neither ever reaches opencode.
        variant_cycle = "<leader>v";
        session_background = "<leader>b";
        sidebar_toggle = "<leader>p";

        # Readline in the prompt: ctrl+p walks prompt history, so the palette
        # moves to M-x. ctrl+shift+p is wezterm's own palette; ctrl+n cannot be
        # bound at all - the input widget swallows it before the keymap.
        history_previous = "up,ctrl+p";
        command_list = "alt+x,<leader>space";

        # Leave ctrl+g inert rather than jumping to the first message - emacs
        # muscle memory presses it to abort.
        messages_first = "home";

        # Message focus, unbound upstream, so `<leader>y` could only ever copy
        # one message. h/k are up/down in every editor here.
        messages_previous = "<leader>h";
        messages_next = "<leader>k";
        messages_toggle_conceal = "<leader>o"; # Was `<leader>h`.

        # Unbound upstream. tool_details/display_thinking mirror claude-code;
        # diff_open has no default at all, so the viewer is unreachable.
        diff_open = "<leader>d";
        tool_details = "ctrl+r";
        session_rename = "none";
        display_thinking = "ctrl+o";
        # `<leader>s` was status_view, which is still `/status` and in the
        # palette; the skill picker has no other front door.
        prompt_skills = "<leader>s";
        status_view = "none";
        help_show = "<leader>?";
      };
    };

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
    # opencode's built-in nord carries a light variant for every key, but which
    # one it uses comes from querying the terminal - and that answer is tmux's,
    # not the terminal's, whenever opencode runs inside tmux. This is the same
    # palette with the light side flattened out, so picking it is decisive.
    themes.nord-light = ./themes/nord-light.json;

    # agents = {};
    # commands = {};
  };

  # opencode reads its TUI config from this path, so the hook can own a copy
  # with the theme swapped and leave home-manager's file alone. Guarded: with
  # no hook to write it, the path would not exist.
  home.sessionVariables = lib.mkIf config.dotless.appearance.enable {
    OPENCODE_TUI_CONFIG = "${config.xdg.configHome}/opencode/tui-active.json";
  };

  dotless.appearance.path = [ pkgs.jq ];

  # Startup-read, like diffnav: the next session gets the new theme.
  dotless.appearance.hooks.opencode = ''
    # Not `[ ... ] && theme=...`: under errexit a false test ends the hook.
    if [ "$mode" = light ]; then
      theme=nord-light
    else
      theme=nord
    fi

    jq --arg theme "$theme" '.theme = $theme' \
      "${config.xdg.configHome}/opencode/tui.json" \
      >"${config.xdg.configHome}/opencode/tui-active.json"
  '';
}
