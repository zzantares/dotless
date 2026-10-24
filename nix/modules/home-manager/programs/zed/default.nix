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

    userSettings = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Link <flakeRoot>/config/zed/settings.json into ~/.config/zed, out of
        the store, so it stays editable without a rebuild and Zed's own UI can
        write it. Zed merges it over dotless's global_settings.json, per field
        and recursively.

        Declared, not detected: dotless cannot probe your home purely. Leave it
        false to manage the path yourself, or not at all.
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

      # Colemak navigation: k down, h up, j left, l right. Real motions, and
      # `operator` in the context, so counts (5k) and operator+motion (dk, yk)
      # compose. SendKeystrokes drops both.
      {
        context = "vim_mode == normal || vim_mode == visual || vim_mode == operator";
        bindings = {
          "k" = "vim::Down";
          "h" = "vim::Up";
          "j" = "vim::Left";
          "l" = "vim::Right";
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
          "k" = "menu::SelectNext";
          "h" = "menu::SelectPrevious";
          "space o p" = "project_panel::ToggleFocus";
        };
      }
      {
        context = "vim_mode == insert";
        bindings."ctrl-f" = "editor::MoveRight";
      }
      {
        context = "vim_mode == normal";
        bindings = {
          # Keystrokes split on "-": "ctrl+tab" names a key that does not exist.
          "g b" = [
            "workspace::SendKeystrokes"
            "ctrl-tab"
          ];
          "space o p" = "project_panel::ToggleFocus";

          # Doom's `SPC t t` and nvim's `<leader>tt` open a file browser at
          # the current file; the panel is the nearest zed has.
          "space t t" = "pane::RevealInProjectPanel";
        };
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
        # The consumer's layer, which Zed merges over dotless's. dotless never
        # generates it; opting in only links their repo's copy.
        // lib.optionalAttrs cfg.userSettings {
          "zed/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${userDir}/settings.json";
        }
    );
  };
}
