{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.dotless.appearance;

  # GNOME's toggle is the source of truth. `color-scheme` is also what the XDG
  # settings portal serves as org.freedesktop.appearance, so portal-aware apps
  # (Zed, WezTerm, GTK) follow it with no help from us; this script is only for
  # the ones that can't.
  schemaKey = "org.gnome.desktop.interface color-scheme";

  # One subshell each, so an app that is missing or wedged cannot stop the rest
  # from repainting.
  hookBlocks = lib.concatMapStringsSep "\n" (hook: ''
    if ! (
    ${hook}
    ); then
      echo "appearance-switch: a hook failed" >&2
    fi
  '') cfg.hooks;

  switch = pkgs.writeShellApplication {
    name = "appearance-switch";
    runtimeInputs = [ pkgs.glib ] ++ cfg.path;
    text = ''
      mode=''${1:-auto}

      if [ "$mode" = auto ]; then
        # No GNOME, no schema: there is nothing to follow, so stay dark.
        case "$(gsettings get ${schemaKey} 2>/dev/null || echo prefer-dark)" in
          *prefer-light*) mode=light ;;
          *) mode=dark ;;
        esac
      fi

      case "$mode" in
        light | dark) ;;
        *)
          echo "appearance-switch: expected light, dark or auto; got '$mode'" >&2
          exit 2
          ;;
      esac

      state=${lib.escapeShellArg cfg.stateFile}
      mkdir -p "$(dirname "$state")"
      printf '%s\n' "$mode" >"$state"

      ${hookBlocks}
    '';
  };

in
{
  options.dotless.appearance = {
    enable = lib.mkEnableOption "light/dark palette switching driven by the GNOME appearance toggle";

    hooks = lib.mkOption {
      type = lib.types.listOf lib.types.lines;
      default = [ ];
      description = ''
        Shell snippets run on every switch with `$mode` set to `light` or
        `dark`. Each program module adds its own repaint. Each runs in its own
        subshell, so one failing only costs that app its repaint.
      '';
    };

    path = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra packages the hooks need on PATH.";
    };

    stateFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/dotless/appearance";
      defaultText = "$XDG_STATE_HOME/dotless/appearance";
      description = "Holds the current mode, for programs that read it at startup.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ switch ];

    # Hooks read files that linkGeneration has just put in place, and a fresh
    # generation may have changed a palette, so repaint on every activation.
    home.activation.appearanceSwitch = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${switch}/bin/appearance-switch auto
    '';

    # `gsettings monitor` prints a line per change and never exits.
    systemd.user.services = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      appearance-switch = {
        Unit = {
          Description = "Repaint terminals and editors on a GNOME appearance change";
          PartOf = [ "graphical-session.target" ];
        };

        Service = {
          Type = "simple";
          ExecStartPre = "${switch}/bin/appearance-switch auto";
          ExecStart = toString (
            pkgs.writeShellScript "appearance-watch" ''
              ${pkgs.glib}/bin/gsettings monitor ${schemaKey} | while read -r _; do
                ${switch}/bin/appearance-switch auto
              done
            ''
          );
          Restart = "on-failure";
          RestartSec = 5;
        };

        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
