# Status-bar palettes. Every style that reads one lives in `styles` below, so a
# re-source repaints a running server completely.
{
  palettes = {
    # Catppuccin
    dark = {
      bg = "#1e1e28";
      fg = "#dadae8";
      cyan = "#c2e7f0";
      black = "#15121c";
      gray = "#332e41";
      magenta = "#c6aae8";
      pink = "#e5b4e2";
      red = "#e38c8f";
      green = "#b1e3ad";
      yellow = "#ebddaa";
      blue = "#a4b9ef";
      orange = "#f9c096";
      black4 = "#575268";
    };

    # Solarized Light. base3 is the canvas, base2 the status segments, base1 the
    # in-pane selection block; the accents are Solarized's, unchanged.
    light = {
      bg = "#fdf6e3";
      fg = "#586e75";
      cyan = "#2aa198";
      black = "#eee8d5";
      gray = "#eee8d5";
      magenta = "#6c71c4";
      pink = "#d33682";
      red = "#dc322f";
      green = "#859900";
      yellow = "#b58900";
      blue = "#268bd2";
      orange = "#cb4b16";
      black4 = "#93a1a1";
    };
  };

  # `claudeStatus` is the path to the attention-marker script.
  styles =
    palette: claudeStatus: with palette; ''
      # status
      set -g status-position bottom
      set -g status "on"
      set -g status-bg "${bg}"
      set -g status-justify "left"
      set -g status-left-length "100"
      set -g status-right-length "100"

      # messages
      # Keep left-aligned: align=centre makes the rename prompt overlap the prompt.
      set -g message-style fg="${cyan}",bg="${gray}"
      set -g message-command-style fg="${cyan}",bg="${gray}"

      # panes
      set -g pane-border-style fg="${gray}"
      set -g pane-active-border-style fg="${blue}"

      # windows
      setw -g window-status-activity-style fg="${fg}",bg="${bg}",none
      setw -g window-status-separator ""
      setw -g window-status-style fg="${fg}",bg="${bg}",none

      # --------=== Statusline

      set -g status-left "#[fg=${green},bg=${gray}] #S "

      # `yellow` is the ANSI slot, so it tracks the terminal palette on its own.
      set -g status-right "#[fg=yellow]#(${claudeStatus} #S)#[default] %H:%M"

      setw -g window-status-format "#[fg=${bg},bg=${blue}] #I #[fg=${fg},bg=${gray}] #{?window_name,#{b:window_name},#{b:pane_current_command}} "
      setw -g window-status-current-format "#[fg=${bg},bg=${orange}] #I #[fg=${fg},bg=${bg}] #{?window_name,#{b:window_name},#{b:pane_current_command}} "

      # --------=== Modes
      setw -g clock-mode-colour "${blue}"
      setw -g mode-style "fg=${pink} bg=${black4} bold"
    '';
}
