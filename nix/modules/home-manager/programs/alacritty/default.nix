{
  profile,
  config,
  lib,
  pkgs,
  ...
}:

let
  themes = import ./colors.nix;
  tomlFormat = pkgs.formats.toml { };

  # Alacritty has no idea the desktop has a light mode, so the palette lives in
  # an imported file that `appearance-switch` overwrites. `live_config_reload`
  # watches imports too, so running windows repaint without a restart.
  activeColors = "${config.xdg.configHome}/alacritty/colors-active.toml";
  paletteFile = name: tomlFormat.generate "alacritty-${name}.toml" { colors = themes.${name}; };

  palettes = {
    dark = paletteFile profile.alacrittyColors;
    light = paletteFile (profile.alacrittyColorsLight or "solarized-light");
  };

in
{
  # Brings the `dotless.appearance` options this module sets.
  imports = [ ./../../appearance ];

  programs.alacritty = {
    enable = lib.mkDefault true;
    package =
      if pkgs.stdenv.hostPlatform.isDarwin then pkgs.alacritty else config.lib.nixGL.wrap pkgs.alacritty;

    settings = {
      general.import = [ activeColors ];

      terminal.shell = {
        # Login processing (-l) happens here; tux itself just decides whether
        # to attach to an existing session or start a new one, same as when
        # typed manually at an interactive prompt.
        program = "${config.programs.zsh.package}/bin/zsh";
        args = [
          "-l"
          "-c"
          "${pkgs.tux}/bin/tux"
        ];
      };

      window = {
        opacity = 1.0;
        dimensions.columns = 80;
        dimensions.lines = 24;
        padding.x = 0;
        padding.y = 0;

        decorations = "none";
        # Leave the startup mode at Alacritty's default ("Windowed"). Forge only
        # tiles windows in mutter's "normal" state; a window that starts
        # "Maximized" (or "Fullscreen") stays in mutter's maximized state and
        # Forge won't manage it - it just fills the work area and covers the
        # other tiles, so Alacritty could never share a workspace. Keep windowed
        # so Forge tiles it alongside siblings on launch.
        # startup_mode = "Maximized";
        # startup_mode = "Fullscreen";
      };

      font = {
        size = 12;
        offset.x = 0;
        offset.y = 6;

        normal.family = "CaskaydiaCove Nerd Font";
        normal.style = "Regular";
      };

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

  xdg.configFile = {
    "alacritty/colors-dark.toml".source = palettes.dark;
    "alacritty/colors-light.toml".source = palettes.light;
  };

  # A copy, not a symlink: alacritty watches the import path, and swapping a
  # symlink underneath it fires no inotify event.
  dotless.appearance.hooks.alacritty = ''
    install -m644 "${config.xdg.configHome}/alacritty/colors-$mode.toml" ${lib.escapeShellArg activeColors}
  '';
}
