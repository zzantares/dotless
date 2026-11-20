{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.dotless.appearance;

  # The cross-desktop appearance setting, and the names needed to read it.
  portalName = "org.freedesktop.portal.Desktop";
  portalPath = "/org/freedesktop/portal/desktop";
  portalIface = "org.freedesktop.portal.Settings";
  portalSetting = "org.freedesktop.appearance color-scheme";

  # Embedded in double quotes so the single quotes D-Bus wants survive and the
  # generated script stays readable. escapeShellArg would be correct but turns
  # the rule into a thicket of '\'' for anyone reading it.
  matchRule = lib.concatStringsSep "," [
    "type='signal'"
    "interface='${portalIface}'"
    "member='SettingChanged'"
    "arg0='org.freedesktop.appearance'"
  ];

  schemaKey = "org.gnome.desktop.interface color-scheme";

  defaultsBin = "/usr/bin/defaults";

  # What `auto` means per platform. Empty for a platform with no default yet;
  # the assertion below tells the user to name one.
  autoProvider =
    if pkgs.stdenv.hostPlatform.isLinux then
      "linux"
    else if pkgs.stdenv.hostPlatform.isDarwin then
      "darwin"
    else
      "";

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

    watchTarget = lib.mkOption {
      type = lib.types.str;
      default = "graphical-session.target";
      description = ''
        The systemd user target the watcher binds to. GNOME, KDE, Hyprland and
        sway all start `graphical-session.target`, but a hand-written session
        may not, and the watcher never runs if nothing pulls it in.
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
      # GNOME, KDE, Hyprland and sway all serve `org.freedesktop.appearance`
      # over the XDG settings portal, and darkman is a portal backend for a
      # session with no desktop of its own. gsettings is the last resort: dconf
      # still answers where no portal runs at all.
      dotless.appearance.providers.linux = {
        path = [
          pkgs.glib
          pkgs.dbus
          pkgs.gnugrep
        ];

        detect = ''
          portal() {
            gdbus call --session --dest ${portalName} \
              --object-path ${portalPath} \
              --method "${portalIface}.$1" \
              ${portalSetting} 2>/dev/null
          }

          # `Read` is deprecated but answers on an older portal. It wraps the
          # variant twice where ReadOne wraps it once, so match on the digit.
          scheme=$(portal ReadOne || portal Read || true)

          # 1 is prefer-dark and 2 is prefer-light. 0 means the desktop has no
          # preference, which falls through to gsettings like a missing portal.
          case "$scheme" in
            *"uint32 1"*) echo dark ;;
            *"uint32 2"*) echo light ;;
            *)
              # GNOME's Appearance panel sets `default` for Light, not
              # `prefer-light`, and that is the toggle this follows. No answer
              # at all means nothing to follow, so stay dark.
              case "$(gsettings get ${schemaKey} 2>/dev/null || true)" in
                *prefer-dark*) echo dark ;;
                "") echo dark ;;
                *) echo light ;;
              esac
              ;;
          esac
        '';

        watch = ''
          # A session either serves the portal or it does not, and the unit is
          # PartOf graphical-session.target, so decide once at start.
          if gdbus call --session --dest ${portalName} \
               --object-path ${portalPath} \
               --method ${portalIface}.ReadOne \
               ${portalSetting} >/dev/null 2>&1; then
            # The match rule filters on the bus, so no other setting wakes us.
            # dbus-monitor prints a header line and one line per argument; the
            # grep keeps the header, one per signal, and drops the NameAcquired
            # it gets for its own connection.
            dbus-monitor --session "${matchRule}" \
              | grep --line-buffered -F 'member=SettingChanged' \
              | while read -r _; do
                  appearance-switch auto
                done
          else
            # `gsettings monitor` prints a line per change and never exits.
            gsettings monitor ${schemaKey} | while read -r _; do
              appearance-switch auto
            done
          fi
        '';
      };
    }

    {
      # macOS leaves AppleInterfaceStyle unset for Light rather than writing a
      # value, so an exit code is the answer. `defaults` is addressed by
      # absolute path: writeShellApplication only prepends to PATH, and nothing
      # guarantees /usr/bin is on the inherited one.
      dotless.appearance.providers.darwin = {
        path = [ pkgs.dark-mode-notify ];

        detect = ''
          if [ ! -x ${defaultsBin} ]; then
            # Not macOS after all, so nothing to follow: stay dark, as linux
            # does when no portal and no dconf answer.
            echo dark
          elif [ "$(${defaultsBin} read -g AppleInterfaceStyle 2>/dev/null)" = Dark ]; then
            # The test position keeps errexit from treating the Light exit
            # code, which is 1, as fatal.
            echo dark
          else
            echo light
          fi
        '';

        # Runs the command once at startup, on every appearance change, and on
        # wake. It also exports DARKMODE, which we ignore: `auto` re-reads the
        # setting, so there is one answer to the question, not two.
        watch = "dark-mode-notify appearance-switch auto";
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
            PartOf = [ cfg.watchTarget ];
          };

          Service = {
            Type = "simple";
            ExecStartPre = "${switch}/bin/appearance-switch auto";
            ExecStart = "${watcher}/bin/appearance-watch";
            Restart = "on-failure";
            RestartSec = 5;
          };

          Install.WantedBy = [ cfg.watchTarget ];
        };
      };

      # launchd has no graphical-session.target, so the agent loads at login
      # and KeepAlive restarts it. dark-mode-notify runs the switch itself on
      # startup, which is why there is no separate pre-step here.
      launchd.agents = lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin && provider.watch != null) {
        appearance-switch.config = {
          ProgramArguments = [ "${watcher}/bin/appearance-watch" ];
          RunAtLoad = true;
          KeepAlive = true;

          # Ask macOS for the interactive scheduling tier, as the emacs agent
          # does: this repaints what the user is looking at.
          ProcessType = "Interactive";
        };
      };
    })
  ];
}
