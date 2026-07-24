{
  profile,
  config,
  lib,
  pkgs,
  ...
}:

let
  # Convention: if the consumer places config/hypr/local.conf in their flake root,
  # symlink it out-of-store (live-editable, auto-reloads on change, no rebuild needed).
  # Otherwise create an empty placeholder so the `source` directive doesn't error.
  # Evaluated at switch time under --impure.
  userDir = "${config.home.homeDirectory}/${profile.flakeRoot}/config/hypr";
  hasUserConfig = builtins.pathExists "${userDir}/local.conf";

  # Direction mapping (standard HJKL):
  #   h = up, j = left, k = down, l = right
  navKeys = [
    "h"
    "j"
    "k"
    "l"
  ];

  # Letter workspaces: all lowercase letters excluding navigation keys.
  # Workspace name matches the Colemak keysym — press the key you see, go to
  # the workspace with that letter.
  workspaceLetters = lib.filter (l: !(builtins.elem l navKeys)) (
    lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz"
  );

  mkWorkspaceBinds = map (l: "SUPER, ${l}, workspace, name:${lib.toUpper l}") workspaceLetters;

  mkMoveToWorkspaceBinds = map (
    l: "SUPER SHIFT, ${l}, movetoworkspace, name:${lib.toUpper l}"
  ) workspaceLetters;

in
{
  imports = [ ./waybar.nix ];

  home.pointerCursor = {
    gtk.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 24;
  };

  gtk = {
    enable = true;
    theme.name = "Adwaita-dark"; # ships with GTK, no package needed
    # GTK4/libadwaita handles dark mode natively via color-scheme; no theme
    # override needed. Explicitly set null to opt into the new HM default.
    gtk4.theme = null;
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    # Note: font is set via gtk.font (writes gtk-font-name to settings.ini),
    # NOT via dconf font-name — Nautilus reads settings.ini in non-GNOME sessions.
    font = {
      name = "Overpass";
      size = 11;
    };
    # Belt-and-suspenders: some GTK3 apps check this flag instead of theme name.
    gtk3.extraConfig."gtk-application-prefer-dark-theme" = 1;
  };

  # GTK4/libadwaita apps read color-scheme from the xdg-desktop-portal-gtk
  # Settings portal. Set both color-scheme and gtk-theme explicitly so there
  # is no ambiguity even if the portal has automatic day/night switching enabled
  # (triggered by geoclue2 being available for gammastep).
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "Adwaita-dark";
  };

  # Propagate GTK_THEME to the systemd user environment so D-Bus-activated
  # apps (not launched as Hyprland children) also get the dark variant.
  systemd.user.sessionVariables.GTK_THEME = "Adwaita:dark";

  # gpg-agent handles GPG key operations; pinentry-gnome3 provides the
  # passphrase prompt and can persist the passphrase in gnome-keyring
  # ("Save in password manager" checkbox) so it survives across sessions.
  services.gpg-agent = {
    enableSshSupport = false;
    pinentry.package = pkgs.pinentry-gnome3;
  };

  # Standalone SSH agent as a systemd user service. gnome-keyring's SSH
  # component is deprecated in recent versions and unreliable in non-GNOME
  # sessions. With addKeysToAgent=yes in the SSH config, the passphrase is
  # prompted once per session and then cached for the session lifetime.
  services.ssh-agent.enable = true;

  wayland.windowManager.hyprland = {
    enable = lib.mkDefault true;
    # TODO: migrate extraConfig (submap section) to Lua and switch to "lua"
    configType = "hyprlang";

    settings = {
      input = {
        follow_mouse = 1;
        kb_layout = "us";
        kb_variant = "colemak";
        kb_options = "ctrl:nocaps";
        touchpad = {
          natural_scroll = true;
          disable_while_typing = true;
        };
      };

      cursor = {
        no_hardware_cursors = true;
      };

      env = [
        # QT_QPA_PLATFORMTHEME is set by the HM qt module in shell session vars,
        # but apps launched from Hyprland don't source the shell profile.
        # Setting it here ensures Qt apps (VLC, qBittorrent, etc.) see it.
        "QT_QPA_PLATFORMTHEME,gtk3"
        # Force GTK3 dark variant regardless of launch context — the dconf
        # color-scheme setting only reaches apps via the settings portal,
        # which isn't guaranteed for all GTK3 apps outside a GNOME session.
        "GTK_THEME,Adwaita:dark"
      ];

      "exec-once" = [
        # Propagate compositor env to systemd user session (needed for portals, services).
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland"
        # Polkit authentication agent (required for privilege escalation dialogs).
        "${pkgs.hyprpolkitagent}/lib/hyprpolkitagent"
        # NetworkManager secrets agent — required for auto-connecting to saved
        # WiFi networks. Without this, NM can't retrieve passwords from the
        # keyring and prompts interactively (or fails). No --indicator flag:
        # on pure Wayland GtkStatusIcon is a no-op so no tray icon appears,
        # but the D-Bus secrets agent still registers correctly.
        "${pkgs.networkmanagerapplet}/bin/nm-applet"
        # Wallpaper daemon + initial wallpaper from profile.
        # awww wait blocks until the daemon socket is ready, preventing the
        # race condition where awww img fires before the daemon is up.
        # Note: the package is named awww (a fork of swww); binaries are
        # awww/awww-daemon, not swww/swww-daemon.
        "${pkgs.awww}/bin/awww-daemon"
        "${pkgs.awww}/bin/awww wait && ${pkgs.awww}/bin/awww img ${profile.wallpaper}"
        # Clipboard history — watch both text and image events.
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
      ];

      general = {
        gaps_in = 10;
        gaps_out = 10;
        border_size = 2;
        layout = "dwindle";
      };

      decoration = {
        rounding = 10;
      };

      animations = {
        enabled = true;
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
      };

      bind =
        [
          # ── Essentials ──
          "SUPER, Return, exec, wezterm"
          "SUPER CTRL, t, exec, alacritty"
          "SUPER CTRL, e, exec, emacsclient -c -a emacs"
          "SUPER CTRL, f, exec, firefox"
          "SUPER CTRL, period, exec, nautilus"
          "SUPER CTRL, v, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy"
          "SUPER SHIFT, backspace, killactive"
          "SUPER, space, exec, wofi --show drun"

          # ── Focus (HJKL) ──
          "SUPER, h, movefocus, u"
          "SUPER, j, movefocus, l"
          "SUPER, k, movefocus, d"
          "SUPER, l, movefocus, r"

          # ── Move window ──
          "SUPER SHIFT, h, movewindow, u"
          "SUPER SHIFT, j, movewindow, l"
          "SUPER SHIFT, k, movewindow, d"
          "SUPER SHIFT, l, movewindow, r"

          # ── Layout ──
          "SUPER, slash, layoutmsg, togglesplit" # tiles horizontal ↔ vertical
          "SUPER, comma, fullscreen, 1" # zoom focused window, press again to restore

          # ── Resize ──
          "SUPER, minus, resizeactive, -50 -50"
          "SUPER, equal, resizeactive, 50 50"

          # ── Numbered workspaces ──
          "SUPER, 1, workspace, 1"
          "SUPER, 2, workspace, 2"
          "SUPER, 3, workspace, 3"
          "SUPER, 4, workspace, 4"
          "SUPER, 5, workspace, 5"
          "SUPER, 6, workspace, 6"
          "SUPER, 7, workspace, 7"
          "SUPER, 8, workspace, 8"
          "SUPER, 9, workspace, 9"

          "SUPER SHIFT, 1, movetoworkspace, 1"
          "SUPER SHIFT, 2, movetoworkspace, 2"
          "SUPER SHIFT, 3, movetoworkspace, 3"
          "SUPER SHIFT, 4, movetoworkspace, 4"
          "SUPER SHIFT, 5, movetoworkspace, 5"
          "SUPER SHIFT, 6, movetoworkspace, 6"
          "SUPER SHIFT, 7, movetoworkspace, 7"
          "SUPER SHIFT, 8, movetoworkspace, 8"
          "SUPER SHIFT, 9, movetoworkspace, 9"

          # ── Workspace navigation ──
          "SUPER, tab, workspace, previous" # back-and-forth
          "SUPER SHIFT, tab, movecurrentworkspacetomonitor, +1"

          # ── Media / hardware keys ──
          # Brightness: backlight device names vary per machine; add to local.conf:
          #   bindel = , XF86MonBrightnessUp, exec, swayosd-client --brightness raise --device <dev>
          #   bindel = , XF86MonBrightnessDown, exec, swayosd-client --brightness lower --device <dev>
          ", XF86AudioRaiseVolume, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume raise; ${pkgs.pipewire}/bin/pw-play ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/audio-volume-change.oga"
          ", XF86AudioLowerVolume, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume lower; ${pkgs.pipewire}/bin/pw-play ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/audio-volume-change.oga"
          ", XF86AudioMute, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume mute-toggle; ${pkgs.pipewire}/bin/pw-play ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/audio-volume-change.oga"

          # ── Screenshots (grimblast: copy + save to ~/Pictures/Screenshots) ──
          ", Print, exec, grimblast --notify copysave screen"
          "SHIFT, Print, exec, grimblast --notify copysave area"
          "SUPER, Print, exec, grimblast --notify copysave active"

          # ── Service submap (physical ; → Colemak O) ──
          "SUPER SHIFT, o, submap, service"

          # ── Files workspace ──
          "SUPER, period, workspace, name:."
          "SUPER SHIFT, period, movetoworkspace, name:."
        ]
        ++ mkWorkspaceBinds
        ++ mkMoveToWorkspaceBinds;

      # ── Window auto-placement ──
      # Hyprland 0.55: match properties use "match:prop regex" syntax.
      windowrule = [
        "workspace name:E, match:class (emacs|Emacs)"
        "workspace name:T, match:class (org\\.wezfurlong\\.wezterm|Alacritty)"
        "workspace name:F, match:class (firefox|Firefox)"
        "workspace name:., match:class (org\\.gnome\\.Nautilus|nautilus)"
      ];
    };

    # Service submap (modal keybindings, like AeroSpace's service mode).
    # Keys are mnemonic (f = float) using Colemak characters.
    extraConfig = ''
      submap = service
      bind = , escape, submap, reset
      bind = , f, exec, hyprctl --batch "dispatch togglefloating ; dispatch submap reset"
      bind = , r, exec, hyprctl reload && hyprctl dispatch submap reset && notify-send -u low -t 2000 "Hyprland" "Config reloaded"
      bind = , l, exec, hyprlock
      submap = reset

      # Per-consumer overrides — sourced last so they can override anything above.
      # Create config/hypr/local.conf in your flake root to customise without rebuilding.
      source = ${config.home.homeDirectory}/.config/hypr/local.conf
    '';
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        disable_loading_bar = true;
        hide_cursor = true;
      };
      background = [
        {
          monitor = "";
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
          brightness = 0.5;
        }
      ];
      "input-field" = [
        {
          monitor = "";
          size = "300, 50";
          outline_thickness = 2;
          outer_color = "rgb(8ba4b0)";
          inner_color = "rgb(282727)";
          font_color = "rgb(c5c9c5)";
          fade_on_empty = true;
          hide_input = true;
          placeholder_text = "<i>Password</i>";
          check_color = "rgb(87a987)";
          fail_color = "rgb(c4746e)";
          fail_text = "<i>$FAIL</i>";
        }
      ];
      label = [
        {
          monitor = "";
          text = "$TIME";
          color = "rgba(c5c9c5ff)";
          font_size = 64;
          font_family = "Overpass";
          halign = "center";
          valign = "center";
          position = "0, 200";
        }
        {
          monitor = "";
          text = ''cmd[update:60000]echo "$(date +"%A, %B %d")"'';
          color = "rgba(a09e9cff)";
          font_size = 18;
          font_family = "Overpass";
          halign = "center";
          valign = "center";
          position = "0, 130";
        }
      ];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        after_sleep_cmd = "hyprctl dispatch dpms on";
        ignore_dbus_inhibit = false;
        lock_cmd = "hyprlock";
      };
      listener = [
        {
          # Dim screen after 5 minutes of inactivity.
          timeout = 300;
          "on-timeout" = "${pkgs.brightnessctl}/bin/brightnessctl -s set 10%";
          "on-resume" = "${pkgs.brightnessctl}/bin/brightnessctl -r";
        }
        {
          # Lock screen after 10 minutes.
          timeout = 600;
          "on-timeout" = "hyprlock";
        }
        {
          # Suspend after 15 minutes — only when on battery (never on AC).
          timeout = 900;
          "on-timeout" = "grep -ql 1 /sys/class/power_supply/*/online || systemctl suspend";
        }
      ];
    };
  };

  services.mako = {
    enable = true;
    settings = {
      font = "Overpass 12";
      "background-color" = "#1d1c19ee";
      "text-color" = "#c5c9c5";
      "border-color" = "#8ba4b0";
      "border-radius" = 8;
      "border-size" = 2;
      "default-timeout" = 5000;
      padding = "12";
      width = 320;
      height = 100;
      "max-icon-size" = 32;
      layer = "overlay";
    };
  };

  # At boot NM tries to WiFi autoconnect before the user session exists, so
  # gnome-keyring is locked and nm-applet (secrets agent) isn't running yet.
  # NM times out the secrets request (~60 s) and gives up. This oneshot service
  # runs after the graphical session is up — gnome-keyring is unlocked via PAM
  # at SDDM login, nm-applet is registered — and reconnects the WiFi device if
  # NM didn't manage to connect on its own. Works for every network, no per-SSID
  # configuration needed.
  systemd.user.services.nm-wifi-reconnect =
    let
      script = pkgs.writeShellScript "nm-wifi-reconnect" ''
        # Give nm-applet a moment to register as NM secrets agent.
        sleep 5
        # Nothing to do if already connected (e.g. Ethernet is up, or NM was fast enough).
        ${pkgs.networkmanager}/bin/nmcli -t -f STATE general | grep -qx "connected" && exit 0
        # Find the first WiFi device and connect it. NM picks the best autoconnect
        # connection and retrieves the password from gnome-keyring via nm-applet.
        WIFI_DEV=$(${pkgs.networkmanager}/bin/nmcli -t -f DEVICE,TYPE device \
          | awk -F: '$2 == "wifi" {print $1; exit}')
        [ -n "$WIFI_DEV" ] && ${pkgs.networkmanager}/bin/nmcli device connect "$WIFI_DEV" || true
      '';
    in
    {
      Unit = {
        Description = "Reconnect WiFi after secrets agent becomes available";
        After = [ "graphical-session.target" ];
        Wants = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${script}";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

  # Removable media automounter — no tray icon; mako notifications handle feedback.
  # Depends on udisks2, which is already running via services.gvfs at the NixOS level.
  systemd.user.services.udiskie = {
    Unit = {
      Description = "udiskie automounter";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.udiskie}/bin/udiskie";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # swayosd-server as a systemd user service so it starts with the session
  # and restarts on crash — more robust than exec-once.
  systemd.user.services.swayosd-server = {
    Unit = {
      Description = "SwayOSD server";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.swayosd}/bin/swayosd-server";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Consumer override: live symlink when provided, empty placeholder otherwise.
  xdg.configFile."hypr/local.conf" =
    if hasUserConfig
    then { source = config.lib.file.mkOutOfStoreSymlink "${userDir}/local.conf"; }
    else { text = ""; };

  home.packages = with pkgs; [
    blueman
    cliphist
    grimblast
    imv
    udiskie
    wl-clipboard
    wofi
    pavucontrol
    brightnessctl
    hyprpolkitagent
    networkmanagerapplet
    libnotify
    swayosd
    awww
  ];

  # Automatic display profile switching on monitor connect/disconnect.
  # Profiles are machine-specific and defined at the configuration level.
  services.kanshi.enable = true;

  # Blue light filter — warms color temperature at night using geoclue2 for
  # automatic sunrise/sunset times (geoclue2 is enabled at the NixOS level).
  services.gammastep = {
    enable = true;
    provider = "geoclue2";
    temperature = {
      day = 6500;
      night = 3500;
    };
  };

  # Qt apps follow the GTK theme so they match Adwaita Dark without a separate Qt theme.
  qt = {
    enable = true;
    platformTheme.name = "gtk3";
  };

  # TUI file manager
  programs.yazi = {
    enable = true;
    shellWrapperName = "y";
  };

  # PDF viewer with Colemak navigation: h=up, j=left, k=down, l=right
  programs.zathura = {
    enable = true;
    options = {
      recolor = false; # start in normal mode; toggle night mode with Ctrl+r
      recolor-lightcolor = "#1d1d1d"; # Adwaita Dark background
      recolor-darkcolor = "#eeeeec";  # Adwaita Dark foreground
      selection-clipboard = "clipboard";
      adjust-open = "best-fit";
    };
    mappings = {
      k = "scroll down";
      h = "scroll up";
      j = "scroll left";
      l = "scroll right";
      K = "navigate next";
      H = "navigate previous";
      "<C-k>" = "scroll half-down";
      "<C-h>" = "scroll half-up";
    };
  };

  # Declare the screenshots directory via XDG (grimblast respects XDG_SCREENSHOTS_DIR)
  # and ensure it exists via systemd-tmpfiles rather than an imperative activation script.
  xdg.userDirs.extraConfig.XDG_SCREENSHOTS_DIR = "$HOME/Pictures/Screenshots";
  systemd.user.tmpfiles.rules = [ "d %h/Pictures/Screenshots 0755 - - -" ];

  # Wire the system file manager as the default handler for local directories.
  # The GUI file manager itself (e.g. Nautilus) is installed at the NixOS level
  # since that varies per machine; this wires up the xdg-open integration.
  xdg.mimeApps.defaultApplications = {
    "inode/directory" = "org.gnome.Nautilus.desktop";
    "application/pdf" = "org.pwmt.zathura.desktop";

    # Links from non-browser apps (email, Slack, etc.)
    "x-scheme-handler/http" = "firefox.desktop";
    "x-scheme-handler/https" = "firefox.desktop";
    "text/html" = "firefox.desktop";
    "application/xhtml+xml" = "firefox.desktop";

    # Images
    "image/png" = "imv.desktop";
    "image/jpeg" = "imv.desktop";
    "image/gif" = "imv.desktop";
    "image/webp" = "imv.desktop";
    "image/avif" = "imv.desktop";
    "image/tiff" = "imv.desktop";
    "image/bmp" = "imv.desktop";
    "image/svg+xml" = "imv.desktop";

    # Video
    "video/mp4" = "vlc.desktop";
    "video/x-matroska" = "vlc.desktop";
    "video/webm" = "vlc.desktop";
    "video/avi" = "vlc.desktop";
    "video/quicktime" = "vlc.desktop";
    "video/mpeg" = "vlc.desktop";
    "video/ogg" = "vlc.desktop";

    # Audio
    "audio/mpeg" = "vlc.desktop";
    "audio/ogg" = "vlc.desktop";
    "audio/flac" = "vlc.desktop";
    "audio/x-flac" = "vlc.desktop";
    "audio/wav" = "vlc.desktop";
    "audio/aac" = "vlc.desktop";
    "audio/mp4" = "vlc.desktop";
    "audio/opus" = "vlc.desktop";
  };
}
