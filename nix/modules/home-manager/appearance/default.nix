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

  # A script each, not a subshell: bash drops errexit inside a subshell used as
  # a condition or an and-or operand, so an in-process hook would run on past
  # its own failures and report the wrong status.
  hookScript =
    name: hook:
    pkgs.writeShellApplication {
      name = "appearance-hook-${name}";
      runtimeInputs = cfg.path;
      text = ''
        mode="$1"
        ${hook}
      '';
    };

  hookRuns = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: hook:
      "${hookScript name hook}/bin/appearance-hook-${name} \"$mode\" "
      + "|| echo \"appearance-switch: the ${name} hook failed\" >&2"
    ) cfg.hooks
  );

  switch = pkgs.writeShellApplication {
    name = "appearance-switch";
    runtimeInputs = [ pkgs.glib ] ++ cfg.path;
    text = ''
      mode=''${1:-auto}

      if [ "$mode" = auto ]; then
        # No GNOME, no schema: nothing to follow, so stay dark.
        scheme=$(gsettings get ${schemaKey} 2>/dev/null || echo prefer-dark)

        # Only prefer-dark is dark. GNOME's Appearance panel sets `default` for
        # Light, not `prefer-light`, and that is the toggle this follows.
        case "$scheme" in
          *prefer-dark*) mode=dark ;;
          *) mode=light ;;
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

      ${hookRuns}
    '';
  };

in
{
  options.dotless.appearance = {
    enable = lib.mkEnableOption "light/dark palette switching driven by the GNOME appearance toggle";

    hooks = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = { };
      description = ''
        Repaints to run on every switch, keyed by the program they belong to,
        with `$mode` set to `light` or `dark`. Each runs as its own script, so
        one failing costs only that program its repaint and says which.
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
