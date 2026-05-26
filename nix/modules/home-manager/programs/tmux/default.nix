{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

let
  # NOTE see: https://github.com/joshmedeski/t-smart-tmux-session-manager
  # TODO need to separate live sessions from directories when picking tmux sessions `C-t T` (separated with a line)
  t = pkgs.tmuxPlugins.mkTmuxPlugin {
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
    T_SESSION_USE_GIT_ROOT = "true";
  };

  home.sessionPath = [ "${t}/share/tmux-plugins/t/bin" ];

  programs.tmux = {
    enable = lib.mkDefault true;
    mouse = true; # allows to use the wheel to scroll (one never knows)
    aggressiveResize = true;
    baseIndex = 0;
    focusEvents = true;
    clock24 = false;
    escapeTime = 10;
    historyLimit = 10000;
    keyMode = "vi";
    secureSocket = true;
    terminal = "tmux-256color";
    prefix = "C-t";
    shell = "${config.programs.zsh.package}/bin/zsh";

    plugins = [
      {
        plugin = t;
        extraConfig = "set -g detach-on-destroy off";
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
        # Show tmux claude sessions needing attention in the status bar
        set -g status-right "#[fg=yellow]#(${tmux-claude-status}/bin/tmux-claude-status #S)#[default] %H:%M"

        # Creates a menu for tmux-fzf that exposes Claude Code sessions (defined in overlays)
        bind o display-popup -E "${pkgs.tmux-claude-picker}/bin/tmux-claude-picker"
      '')
    ];
  };
}
