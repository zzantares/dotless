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
  #   profile.liveOverrides.zed = true;              # whole ~/.config/zed
  #   profile.liveOverrides.zed = [ "keymap.json" ]; # that file only
  userDir = "${config.home.homeDirectory}/${profile.flakeRoot}/config/zed";
  live = profile.liveOverrides.zed or false;
  liveDir = live == true;
  liveItem = rel: liveDir || (lib.isList live && builtins.elem rel live);

  # Zed accepts a context-less block (global bindings), so context is nullable;
  # drop the null instead of emitting `"context": null`.
  keymapJSON = map (block: lib.filterAttrs (_: v: v != null) block) cfg.keymap;

  # dotless's base layer. Shipped as JSONC verbatim: Zed parses comments, so
  # they stay with the settings they explain.
  globalSettings = ./../../../../../config/zed/global_settings.json;

  fileFor =
    rel: baked:
    if liveItem rel then
      { source = config.lib.file.mkOutOfStoreSymlink "${userDir}/${rel}"; }
    else
      { source = baked; };
in
{
  options.dotless.editors.zed = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether dotless renders Zed's global_settings.json and keymap.json.";
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

    # settings.json is never managed: it is the consumer's layer, which Zed
    # merges over this one and rewrites from its own UI.
    assertions = [
      {
        assertion = !(lib.isList live && builtins.elem "settings.json" live);
        message = ''
          profile.liveOverrides.zed lists "settings.json", which dotless does
          not manage. Zed reads ~/.config/zed/settings.json directly; drop the
          entry.
        '';
      }
    ];

    # Per-file entries, so ~/.config/zed stays a real directory: Zed writes
    # settings.json and other state there.
    xdg.configFile = lib.mkIf cfg.enable (
      if liveDir then
        { "zed".source = config.lib.file.mkOutOfStoreSymlink userDir; }
      else
        {
          "zed/global_settings.json" = fileFor "global_settings.json" globalSettings;
          "zed/keymap.json" = fileFor "keymap.json" (jsonFormat.generate "zed-keymap.json" keymapJSON);
        }
    );
  };
}
