{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

let
  # NOTE see: https://github.com/joshmedeski/t-smart-tmux-session-manager
  # TODO need to separate live sessions from directories when picking tmux sessions `C-b T` (separated with a line)
  t-plugin = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "t";
    rtpFilePath = "t-smart-tmux-session-manager.tmux";
    version = inputs.t.shortRev;
    src = inputs.t;
  };

  # This will add tmux claude sessions needing attention to the tmux status bar
  tmux-claude-status = pkgs.writeShellScriptBin "tmux-claude-status" ''
    #!/usr/bin/env bash
    current_session="$1"
    sessions=""
    for s in $(tmux list-sessions -F '#{session_name}'); do
        [ "$s" = "$current_session" ] && continue
        val=$(tmux show-option -t "$s" -qv @claude_attention 2>/dev/null)
        if [ "$val" = "1" ]; then
            sessions="$sessions ● $s"
        fi
    done
    [ -n "$sessions" ] && echo "$sessions" || echo ""
  '';
in
{
  home.sessionVariables = {
    T_SESSION_USE_GIT_ROOT = lib.mkDefault "true";
  };

  # Put Medeski's session manager on PATH under its upstream name `t`. The plugin
  # installs the script under share/…/bin rather than a top-level bin/, so add that
  # directory directly (no writeShellScriptBin wrapper needed once we keep the `t` name).
  home.sessionPath = [ "${t-plugin}/share/tmux-plugins/t/bin" ];

  programs.tmux = {
    enable = lib.mkDefault true;
    mouse = lib.mkDefault true; # allows to use the wheel to scroll (one never knows)
    aggressiveResize = lib.mkDefault true;
    baseIndex = 0;
    focusEvents = lib.mkDefault true;
    clock24 = false;
    escapeTime = 10;
    historyLimit = 10000;
    keyMode = "vi";
    secureSocket = lib.mkDefault true;
    terminal = "tmux-256color";
    prefix = "C-b";
    shell = "${config.programs.zsh.package}/bin/zsh";

    plugins = [
      {
        plugin = t-plugin;
        extraConfig = ''
          set -g detach-on-destroy off
          set -g @t-bind "B"
          # The plugin only auto-binds one key (@t-bind). Add prefix+T as a second
          # alias to the same picker — `bin/t` ignores which key launched it, so
          # prefix+B and prefix+T are interchangeable.
          bind-key T run-shell "${t-plugin}/share/tmux-plugins/t/bin/t"
        '';
      }
      pkgs.tmuxPlugins.resurrect
      # TODO see: https://github.com/tmux-plugins/tmux-resurrect/blob/master/docs/restoring_vim_and_neovim_sessions.md
      # {
      #   plugin = tmuxPlugins.resurrect;
      #   extraConfig = "set -g @resurrect-strategy-nvim 'session'";
      # }
      {
        plugin = pkgs.tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '60' # minutes
        '';
      }
      pkgs.tmuxPlugins.yank # allow copying text to the clipboard by just selecting text
    ];

    extraConfig = lib.mkMerge [
      (lib.mkBefore (lib.readFile ./tmux.conf))
      (lib.mkAfter ''
        # Second prefix: C-t, in ADDITION to C-b. Its effect is terminal-dependent
        # by design (and self-adapting — same config everywhere):
        #   - WezTerm/Ghostty own C-t as their leader (native workspaces/splits), so
        #     it never reaches tmux; this line is inert (shadowed) in those terminals,
        #     and C-b remains the tmux prefix when nested inside them.
        #   - A passthrough terminal like Alacritty forwards C-t to tmux, where it acts
        #     as a prefix — making tmux the "workspace" layer (prefix+T/B = `t` picker),
        #     a WezTerm-workspaces-like experience without a native multiplexer.
        # `send-prefix -2` lets <prefix> C-t emit a literal C-t to apps running inside.
        set -g prefix2 C-t
        bind C-t send-prefix -2

        # Show tmux claude sessions needing attention in the status bar
        set -g status-right "#[fg=yellow]#(${tmux-claude-status}/bin/tmux-claude-status #S)#[default] %H:%M"

        # Creates a menu for tmux-fzf that exposes Claude Code sessions (defined in overlays)
        bind o display-popup -E "${pkgs.tmux-claude-picker}/bin/tmux-claude-picker"
      '')
    ];
  };
}
