{
  profile,
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.dotless.editors.zed;
  jsonFormat = pkgs.formats.json { };

  # Live override; replaces dotless's version, never merges with it.
  #   profile.liveOverrides.zed = true;                # whole ~/.config/zed
  #   profile.liveOverrides.zed = [ "settings.json" ]; # that file only
  userDir = "${config.home.homeDirectory}/${profile.flakeRoot}/config/zed";
  live = profile.liveOverrides.zed or false;
  liveDir = live == true;
  liveItem = rel: liveDir || (lib.isList live && builtins.elem rel live);

  # Zed accepts a context-less block (global bindings), so context is nullable;
  # drop the null instead of emitting `"context": null`.
  keymapJSON = map (block: lib.filterAttrs (_: v: v != null) block) cfg.keymap;

  fileFor =
    rel: value:
    if liveItem rel then
      { source = config.lib.file.mkOutOfStoreSymlink "${userDir}/${rel}"; }
    else
      { source = jsonFormat.generate "zed-${rel}" value; };
in
{
  options.dotless.editors.zed = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether dotless renders Zed's settings.json and keymap.json.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf jsonFormat.type;
      default = { };
      example = lib.literalExpression ''{ vim_mode = false; theme.dark = lib.mkForce "Ayu Dark"; }'';
      description = ''
        Rendered to ~/.config/zed/settings.json. Definitions merge per key at
        any depth: assign a new key to add it, assign a leaf dotless already
        sets to override it (dotless sets its own leaves with mkDefault).
      '';
    };

    keymap = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          freeformType = jsonFormat.type;
          options = {
            context = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Zed context predicate the block applies to.";
            };

            bindings = lib.mkOption {
              type = lib.types.attrsOf jsonFormat.type;
              default = { };
              description = "Keystroke to action. A null action unbinds the key.";
            };
          };
        }
      );
      default = [ ];
      example = lib.literalExpression ''
        lib.mkAfter [
          {
            context = "Editor";
            bindings."ctrl-h" = "editor::Backspace";
          }
        ]
      '';
      description = ''
        Rendered to ~/.config/zed/keymap.json. Definitions concatenate; Zed
        gives precedence to later blocks, so append with lib.mkAfter to
        override a binding dotless sets.
      '';
    };
  };

  config = {
    # Definitions, not the option `default`: a default is dropped once the
    # consumer defines anything, while definitions merge.
    dotless.editors.zed.settings = lib.mapAttrsRecursive (_: lib.mkDefault) {
      ssh_connections = [
        {
          host = "omnia.local";
          args = [ ];
          projects = [
            { paths = [ "/home/jgutierrez/bitnomial/master" ]; }
            { paths = [ "/home/jgutierrez/bitnomial/spot-markets" ]; }
            { paths = [ "/home/jgutierrez/bitnomial/spot-writer" ]; }
          ];
        }
      ];

      vim_mode = true;
      ui_font_size = 16;
      buffer_font_size = 16;

      theme = {
        mode = "system";
        light = "One Light";
        dark = "Modus Operandi Deuteranopia";
      };

      # clang and gcc read *.C and *.H as C++, and Zed follows them. Treat
      # both as C instead.
      file_types.C = [
        "C"
        "H"
      ];

      vim = {
        toggle_relative_line_numbers = true;
        relative_line_numbers = true;
      };

      languages.C.format_on_save = "on";
    };

    # Plain, so consumer blocks concatenate. mkDefault would drop these the
    # moment a consumer appends one.
    dotless.editors.zed.keymap = [
      {
        context = "Workspace";
        # bindings."shift shift" = "file_finder::Toggle";
        bindings = { };
      }
      {
        context = "Editor && vim_mode == insert && !menu";
        # bindings."j k" = "vim::SwitchToNormalMode";
        bindings = { };
      }
      {
        context = "Pane";
        bindings = {
          "alt-}" = "pane::ActivateNextItem";
          "alt-{" = "pane::ActivatePreviousItem";
        };
      }

      # Colemak navigation: k down, h up, j left, l right.
      {
        context = "vim_mode == normal || vim_mode == visual";
        bindings = {
          "k" = [
            "workspace::SendKeystrokes"
            "down"
          ];
          "h" = [
            "workspace::SendKeystrokes"
            "up"
          ];
          "j" = [
            "workspace::SendKeystrokes"
            "left"
          ];
          "l" = [
            "workspace::SendKeystrokes"
            "right"
          ];
        };
      }
      {
        context = "Dock";
        bindings = {
          "ctrl-w j" = "workspace::ActivatePaneLeft";
          "ctrl-w l" = "workspace::ActivatePaneRight";
          "ctrl-w h" = "workspace::ActivatePaneUp";
          "ctrl-w k" = "workspace::ActivatePaneDown";
        };
      }
      {
        context = "vim_mode == normal || vim_mode == visual";
        bindings = {
          "s" = "vim::PushSneak";
          "shift-s" = "vim::PushSneakBackward";
        };
      }
      {
        context = "vim_mode == visual";
        bindings."shift-x" = "vim::Exchange";
      }
      {
        context = "Editor && !menu";
        bindings."ctrl-s" = "workspace::Save";
      }

      # Neovim's yank behavior: yank to end of line.
      {
        context = "vim_mode == normal && !menu";
        bindings."shift-y" = [
          "workspace::SendKeystrokes"
          "y $"
        ];
      }
      {
        context = "ProjectPanel && not_editing";
        bindings = {
          "k" = [
            "workspace::SendKeystrokes"
            "down"
          ];
          "h" = [
            "workspace::SendKeystrokes"
            "up"
          ];
          "space o p" = "project_panel::ToggleFocus";
        };
      }
      {
        context = "vim_mode == insert";
        bindings."ctrl-f" = [
          "workspace::SendKeystrokes"
          "right"
        ];
      }
      {
        context = "vim_mode == normal";
        bindings = {
          "g b" = [
            "workspace::SendKeystrokes"
            "ctrl+tab"
          ];
          "space o p" = "project_panel::ToggleFocus";

          # Doom's `SPC t t` and nvim's `<leader>tt` open a file browser at
          # the current file; the panel is the nearest zed has.
          "space t t" = "pane::RevealInProjectPanel";
        };
      }
    ];

    # Per-file entries, so ~/.config/zed stays a real directory: Zed writes
    # other state there (and rewrites settings.json from its own UI).
    xdg.configFile = lib.mkIf cfg.enable (
      if liveDir then
        { "zed".source = config.lib.file.mkOutOfStoreSymlink userDir; }
      else
        {
          "zed/settings.json" = fileFor "settings.json" cfg.settings;
          "zed/keymap.json" = fileFor "keymap.json" keymapJSON;
        }
    );
  };
}
