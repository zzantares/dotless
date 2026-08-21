{
  profile,
  config,
  lib,
  pkgs,
  ...
}:

let
  # Convention: if the consumer sets profile.liveOverrides.hyprland, symlink their
  # config/hypr/local.lua out-of-store (live-editable, auto-reloads, no rebuild).
  # Otherwise create an empty placeholder so the dofile loader below finds a file.
  #
  # DECLARED, not detected: this used to probe local.lua with builtins.pathExists,
  # which is impure (needs --impure) and aborts eval in CI where the runner can't read
  # the user's home. TODO(dotless#48): pure, shared live-override mechanism.
  userDir = "${config.home.homeDirectory}/${profile.flakeRoot}/config/hypr";
  hasUserConfig = profile.liveOverrides.hyprland or false;

  # Behavior (startup, keybinds, service submap) lives in behavior.lua and calls
  # bare command names. Anything that needs a Nix store path is a named wrapper
  # installed on PATH below, so the Lua file stays static - lintable and
  # syntax-highlighted, with no Nix interpolation.

  # AeroSpace-accordion-style zoom. The focused window floats at this size,
  # centered, so the surrounding tiles peek out at the edges (dimmed via the
  # decoration block below) - a visual reminder that windows are stacked behind,
  # unlike fullscreen which hides them entirely.
  zoomWindow = "dispatch resizeactive exact 95% 95% ; dispatch centerwindow";

  # SUPER+comma toggles the zoom on the focused window's current float state:
  # float+size on the way in, back into the tile on the way out.
  accordionZoom = pkgs.writeShellScriptBin "hypr-accordion-zoom" ''
    if [ "$(hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r .floating)" = true ]; then
      hyprctl dispatch togglefloating
    else
      hyprctl --batch "dispatch togglefloating ; ${zoomWindow}"
    fi
  '';

  # Stack navigation while zoomed: drop the current window into the tile, move
  # to the next/prev tiled window, and hand it the zoom - so the background app
  # swaps into the big window. When not zoomed, fall back to geometric movefocus.
  #   $1 = cyclenext flags ("tiled" forward, "prev tiled" back)
  #   $2 = movefocus fallback direction (u/d/l/r)
  accordionNav = pkgs.writeShellScriptBin "hypr-accordion-nav" ''
    if [ "$(hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r .floating)" = true ]; then
      hyprctl --batch "dispatch togglefloating ; dispatch cyclenext $1 ; dispatch togglefloating ; ${zoomWindow}"
    else
      hyprctl dispatch movefocus "$2"
    fi
  '';

  # Volume-change feedback sound (freedesktop theme, played via PipeWire).
  playSound = pkgs.writeShellScriptBin "hypr-play-sound" ''
    exec ${pkgs.pipewire}/bin/pw-play ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/audio-volume-change.oga
  '';

  # Polkit authentication agent (privilege-escalation dialogs). It ships under
  # /lib, so wrap it to get a PATH-resolvable name for the startup sequence.
  polkitAgent = pkgs.writeShellScriptBin "hypr-polkit-agent" ''
    exec ${pkgs.hyprpolkitagent}/lib/hyprpolkitagent
  '';

  # Initial wallpaper from the profile. awww wait blocks until the daemon socket
  # is ready so awww img doesn't race ahead of it.
  setWallpaper = pkgs.writeShellScriptBin "hypr-set-wallpaper" ''
    ${pkgs.awww}/bin/awww wait && exec ${pkgs.awww}/bin/awww img ${profile.wallpaper}
  '';

in
{
  imports = [ ./waybar.nix ];

  home.pointerCursor = {
    enable = true;
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
    # Lua config. hyprlang is deprecated since Hyprland 0.55; the Lua format
    # renders each setting as an hl.<name>(...) call.
    # See https://wiki.hypr.land/Configuring/Start/.
    configType = "lua";

    settings = {
      # General keywords (input, layout, decoration, ...) all live under a single
      # config = {...} attrset, which becomes one hl.config({...}) call.
      config = {
        ecosystem.no_update_news = true;

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

        cursor.no_hardware_cursors = true;

        general = {
          gaps_in = 10;
          gaps_out = 10;
          border_size = 2;
          layout = "dwindle";
        };

        decoration = {
          rounding = 10;
          # Dim unfocused windows - makes the accordion zoom (SUPER+comma) read
          # clearly, with the peeking tiles receding behind the focused window.
          dim_inactive = true;
          dim_strength = 0.2;
        };

        animations.enabled = true;

        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
        };
      };

      # env pairs render as hl.env("NAME", "value").
      env = [
        # QT_QPA_PLATFORMTHEME is set by the HM qt module in shell session vars,
        # but apps launched from Hyprland don't source the shell profile.
        # Setting it here ensures Qt apps (VLC, qBittorrent, etc.) see it.
        {
          _args = [
            "QT_QPA_PLATFORMTHEME"
            "gtk3"
          ];
        }
        # Force GTK3 dark variant regardless of launch context - the dconf
        # color-scheme setting only reaches apps via the settings portal,
        # which isn't guaranteed for all GTK3 apps outside a GNOME session.
        {
          _args = [
            "GTK_THEME"
            "Adwaita:dark"
          ];
        }
        # xdg-user-dir doesn't know SCREENSHOTS (non-standard type) so it falls
        # back to PICTURES. Export the var explicitly so grimblast saves to the
        # right directory.
        {
          _args = [
            "XDG_SCREENSHOTS_DIR"
            "${config.home.homeDirectory}/Pictures/Screenshots"
          ];
        }
      ];

      # ── Window auto-placement ── (assign matching windows to a workspace)
      window_rule = [
        {
          workspace = "name:E";
          match.class = "emacs|Emacs";
        }
        {
          workspace = "name:T";
          match.class = "Alacritty|alacritty";
        }
        {
          workspace = "name:F";
          match.class = "firefox|Firefox";
        }
        {
          workspace = "name:W";
          match.class = "librewolf|LibreWolf";
        }
        {
          workspace = "name:.";
          match.class = "org\\.gnome\\.Nautilus|nautilus";
        }
      ];
    };

    # Behavioral config (startup, keybinds, service submap) is written as real
    # Lua in behavior.lua and spliced in verbatim - syntax-highlighted and
    # luacheck-able, with generation as Lua loops instead of Nix `map`. It calls
    # the bare command names the wrappers above put on PATH. The declarative
    # config/env/window_rule stay above as Nix settings (per-consumer override
    # points). local.lua is sourced last so it can override anything.
    extraConfig = ''
      ${builtins.readFile ./behavior.lua}
      pcall(dofile, os.getenv("HOME") .. "/.config/hypr/local.lua")
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
        # Without this, systemd-triggered suspends (e.g. lid close) skip
        # hyprlock entirely and resume straight into the unlocked session.
        before_sleep_cmd = "hyprlock";
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
          # Turn the display off shortly after locking (works on AC too, unlike suspend below).
          timeout = 630;
          "on-timeout" = "hyprctl dispatch dpms off";
          "on-resume" = "hyprctl dispatch dpms on";
        }
        {
          # Suspend after 15 minutes — only when on battery (never on AC).
          timeout = 900;
          "on-timeout" = "grep -ql 1 /sys/class/power_supply/*/online || systemctl suspend";
        }
      ];
    };
  };

  # pkgs.emacs (set by the emacs module) is built with --with-x-toolkit
  # (GTK3+X11), so it only ever runs through XWayland. Under a fractional
  # monitor scale, XWayland clients render at 1x and get bitmap-upscaled by
  # the compositor, producing visibly blurry text next to native Wayland
  # clients (e.g. Alacritty). emacs-pgtk is the same Emacs version built
  # without the X toolkit — a native Wayland client that renders at the
  # correct scale. Only applies if the consumer has enabled programs.emacs.
  programs.emacs.package = lib.mkIf config.programs.emacs.enable pkgs.emacs-pgtk;

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

  # Run nm-applet under a virtual framebuffer so its tray icon lands on an
  # invisible X11 display rather than on the Wayland/SNI tray. This avoids the
  # duplicate WiFi icon next to Waybar's native network module while keeping the
  # D-Bus secrets agent working for WiFi password retrieval.
  #
  # xvfb-run starts a throwaway Xvfb on an auto-assigned display number, sets
  # DISPLAY to it, then exec's nm-applet. With WAYLAND_DISPLAY cleared, GTK
  # falls back to the X11 backend — tray icon goes to the virtual framebuffer
  # (nobody sees it). Waybar is a Wayland client and only reads SNI items; it
  # never touches the X11 XEMBED tray on :99.
  systemd.user.services.nm-applet = {
    Unit = {
      Description = "NetworkManager secrets agent (Xvfb-hidden tray)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.xvfb-run}/bin/xvfb-run -a ${pkgs.networkmanagerapplet}/bin/nm-applet";
      # Clear Wayland display so nm-applet uses the X11 backend provided by
      # xvfb-run; its tray icon ends up on an invisible virtual framebuffer.
      Environment = [ "WAYLAND_DISPLAY=" ];
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
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
  xdg.configFile."hypr/local.lua" =
    if hasUserConfig then
      { source = config.lib.file.mkOutOfStoreSymlink "${userDir}/local.lua"; }
    else
      { text = ""; };

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

    # Behavior-script wrappers, called by their bare names from behavior.lua.
    accordionNav
    accordionZoom
    playSound
    polkitAgent
    setWallpaper
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
      recolor-darkcolor = "#eeeeec"; # Adwaita Dark foreground
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
