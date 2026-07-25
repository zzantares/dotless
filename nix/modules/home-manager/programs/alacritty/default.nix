{
  profile,
  config,
  lib,
  pkgs,
  ...
}:

let
  themes = import ./colors.nix;

  # Attach to the most recently active tmux session, if any exist; otherwise
  # just drop into a plain login shell without creating a new session.
  tmuxAttachScript = pkgs.writeShellScript "alacritty-tmux-attach" ''
    if ${config.programs.tmux.package}/bin/tmux list-sessions >/dev/null 2>&1; then
      last_session=$(${config.programs.tmux.package}/bin/tmux list-sessions -F '#{session_last_attached} #{session_name}' \
        | sort -rn | head -n1 | cut -d' ' -f2-)
      exec ${config.programs.tmux.package}/bin/tmux attach-session -d -t "$last_session"
    fi
    exec ${config.programs.zsh.package}/bin/zsh -l
  '';

in
{
  programs.alacritty = {
    enable = lib.mkDefault true;
    package = if pkgs.stdenv.isDarwin then pkgs.alacritty else config.lib.nixGL.wrap pkgs.alacritty;

    settings = {
      terminal.shell = {
        program = "${tmuxAttachScript}";
        args = [ ];
      };

      window = {
        opacity = 1.0;
        dimensions.columns = 80;
        dimensions.lines = 24;
        padding.x = 0;
        padding.y = 0;

        decorations = "none";
        startup_mode = "Maximized";
        # startup_mode = "Fullscreen";
      };

      font = {
        size = 12;
        offset.x = 0;
        offset.y = 6;

        normal.family = "CaskaydiaCove Nerd Font";
        normal.style = "Regular";
      };

      colors = themes."${profile.alacrittyColors}";

      mouse.bindings = [
        {
          mouse = "Right";
          action = "PasteSelection";
        }
      ];

      selection.save_to_clipboard = true;

      cursor.style = "Block";

      keyboard.bindings = [
        {
          key = "V";
          mods = "Control|Shift";
          action = "Paste";
        }
        {
          key = "C";
          mods = "Control|Shift";
          action = "Copy";
        }
        {
          key = "Insert";
          mods = "Shift";
          action = "PasteSelection";
        }
        {
          key = "Key0";
          mods = "Control";
          action = "ResetFontSize";
        }
        {
          key = "Equals";
          mods = "Control";
          action = "IncreaseFontSize";
        }
        {
          key = "Plus";
          mods = "Control";
          action = "IncreaseFontSize";
        }
        {
          key = "Minus";
          mods = "Control";
          action = "DecreaseFontSize";
        }
        {
          key = "Minus";
          mods = "Control";
          action = "DecreaseFontSize";
        }
        {
          key = "N";
          mods = "Control|Shift";
          action = "SpawnNewInstance";
        }
        {
          key = "Return";
          mods = "Control|Alt";
          action = "ToggleFullscreen";
        }
        {
          key = "Space";
          mods = "Control";
          action = "ToggleViMode";
        }

        # Vi Mode
        {
          key = "J";
          mode = "Vi";
          action = "Left";
        }
        {
          key = "K";
          mode = "Vi";
          action = "Down";
        }
        {
          key = "H";
          mode = "Vi";
          action = "Up";
        }
        {
          key = "Q";
          mode = "Vi";
          action = "ToggleViMode";
        }

        {
          key = "Paste";
          action = "Paste";
        }
        {
          key = "Copy";
          action = "Copy";
        }
        {
          key = "PageUp";
          mods = "Shift";
          action = "ScrollPageUp";
          mode = "~Alt";
        }
        {
          key = "PageDown";
          mods = "Shift";
          action = "ScrollPageDown";
          mode = "~Alt";
        }
        {
          key = "NumpadEnter";
          chars = "\n";
        }
      ];
    };
  };
}
