{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.dotless.appearance;

  # What `auto` means per platform. Empty for a platform with no default yet;
  # the assertion below tells the user to name one.
  autoProvider = if pkgs.stdenv.hostPlatform.isLinux then "linux" else "";

  selected = if cfg.provider == "auto" then autoProvider else cfg.provider;

  # The stub keeps a bad name from throwing here, so the assertion is what the
  # user actually reads.
  provider =
    cfg.providers.${selected} or {
      detect = "echo dark";
      watch = null;
      path = [ ];
    };

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
    runtimeInputs = provider.path ++ cfg.path;
    text = ''
      # Prints light or dark. Supplied by the provider, which owns every
      # desktop-specific command in this module.
      detect() {
        ${provider.detect}
      }

      mode=''${1:-auto}

      if [ "$mode" = auto ]; then
        mode=$(detect)
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

  # `appearance-switch` is on its PATH, so a provider's watch body calls it by
  # name rather than threading a store path through.
  watcher = pkgs.writeShellApplication {
    name = "appearance-watch";
    runtimeInputs = [ switch ] ++ provider.path ++ cfg.path;
    text = provider.watch;
  };

in
{
  options.dotless.appearance = {
    enable = lib.mkEnableOption "light/dark palette switching driven by the desktop's appearance toggle";

    provider = lib.mkOption {
      type = lib.types.str;
      default = "auto";
      description = ''
        Which entry of `providers` supplies the mode. `auto` picks the one for
        this platform.
      '';
    };

    providers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            detect = lib.mkOption {
              type = lib.types.lines;
              description = "Shell that prints `light` or `dark`, and nothing else.";
            };

            watch = lib.mkOption {
              type = lib.types.nullOr lib.types.lines;
              default = null;
              description = ''
                Long-running shell that calls `appearance-switch auto` on every
                change. Null for a provider with no signal to watch, which
                leaves the mode to an explicit `appearance-switch light|dark`.
              '';
            };

            path = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
              description = "Packages `detect` and `watch` need on PATH.";
            };
          };
        }
      );
      default = { };
      description = ''
        Sources for the light/dark signal, keyed by the environment they read.
        Open on purpose: a desktop dotless does not ship can add its own pair
        without a change here.
      '';
    };

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

    fallbacks = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            source = lib.mkOption {
              type = lib.types.path;
              description = "Store path holding the dark palette.";
            };

            target = lib.mkOption {
              type = lib.types.str;
              description = "Path the program reads, which a hook owns when switching is on.";
            };
          };
        }
      );
      default = { };
      description = ''
        Dark palettes to install when switching is off, keyed by the program
        they belong to. A program whose palette only a hook writes reverts to
        its stock theme on a platform with no switch (Darwin), so every such
        path needs an entry here.
      '';
    };

    stateFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/dotless/appearance";
      defaultText = "$XDG_STATE_HOME/dotless/appearance";
      description = "Holds the current mode, for programs that read it at startup.";
    };
  };

  config = lib.mkMerge [
    {
      # GNOME, KDE, Hyprland and sway all serve the XDG settings portal, and
      # darkman is a portal backend for a session with no desktop of its own.
      # gsettings is the last resort: dconf answers with no portal running.
      dotless.appearance.providers.linux = {
        path = [ pkgs.glib ];

        detect = ''
          scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo prefer-dark)

          # Only prefer-dark is dark. GNOME's Appearance panel sets `default`
          # for Light, not `prefer-light`, and that is the toggle this follows.
          case "$scheme" in
            *prefer-dark*) echo dark ;;
            *) echo light ;;
          esac
        '';

        # `gsettings monitor` prints a line per change and never exits.
        watch = ''
          gsettings monitor org.gnome.desktop.interface color-scheme | while read -r _; do
            appearance-switch auto
          done
        '';
      };
    }

    # Nothing repaints these, so they hold the dark palette and stay fresh:
    # installed every activation, since a generation may have changed it.
    (lib.mkIf (!cfg.enable) {
      home.activation.appearanceFallback = lib.hm.dag.entryAfter [ "linkGeneration" ] (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            _: f: "run install -Dm644 ${f.source} ${lib.escapeShellArg f.target}"
          ) cfg.fallbacks
        )
      );
    })

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.providers ? ${selected};
          message =
            if selected == "" then
              "dotless.appearance: no provider for this platform yet; set dotless.appearance.provider."
            else
              "dotless.appearance.provider names '${selected}', which dotless.appearance.providers does not define.";
        }
      ];

      home.packages = [ switch ];

      # Hooks read files that linkGeneration has just put in place, and a fresh
      # generation may have changed a palette, so repaint on every activation.
      home.activation.appearanceSwitch = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${switch}/bin/appearance-switch auto
      '';

      systemd.user.services = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && provider.watch != null) {
        appearance-switch = {
          Unit = {
            Description = "Repaint terminals and editors on a desktop appearance change";
            PartOf = [ "graphical-session.target" ];
          };

          Service = {
            Type = "simple";
            ExecStartPre = "${switch}/bin/appearance-switch auto";
            ExecStart = "${watcher}/bin/appearance-watch";
            Restart = "on-failure";
            RestartSec = 5;
          };

          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
    })
  ];
}
