{
  lib,
  pkgs,
  profile,
  ...
}:

let
  mkTuple = lib.gvariant.mkTuple;

  # TODO these are managed outised of HM (I could try removing and put them in here instead)
  # Getting them from nixpkgs would get me versions not compatible with GNOME Shell version
  # - desktop-icons-ng-ding
  # - x11-gestures

  gnome-extensions = with pkgs.gnomeExtensions; [
    forge
    auto-move-windows # Pin apps to workspaces (sway `assign` equivalent)
    unite
    x11-gestures
  ];

  # ── i3/Hyprland-style fixed workspaces ────────────────────────────────────
  # GNOME/Mutter has no named, on-demand workspaces like Hyprland; it only has
  # a fixed numbered list. We approximate the Hyprland app-workspaces (E/T/F/·)
  # by pinning each app to a fixed slot and giving that slot its Hyprland letter
  # as an extra switch accelerator, alongside the plain number.
  workspaceCount = 9;

  # slot -> { key = extra "<Super>+key" accelerator; app = .desktop id to pin }.
  # Mirrors the Hyprland windowrule class→workspace mapping.
  appSlots = {
    "1" = {
      key = "t";
      app = "org.wezfurlong.wezterm.desktop";
    }; # Terminal
    "2" = {
      key = "e";
      app = "emacs.desktop";
    }; # Emacs
    "3" = {
      key = "f";
      app = "firefox.desktop";
    }; # Firefox
    "4" = {
      key = "period";
      app = "org.gnome.Nautilus.desktop";
    }; # Files
  };

  wsNumbers = lib.genList (i: i + 1) workspaceCount; # [ 1 … 9 ]
  slotKey = n: lib.optional (appSlots ? ${toString n}) "<Super>${appSlots.${toString n}.key}";

  # Switch: <Super>N (+ the app letter for pinned slots).
  switchWorkspaceBinds = lib.listToAttrs (
    map (
      n: lib.nameValuePair "switch-to-workspace-${toString n}" ([ "<Super>${toString n}" ] ++ slotKey n)
    ) wsNumbers
  );
  # Move window to workspace: <Super><Shift>N only (letters kept for Forge's
  # in-workspace stack/tab toggles, which live on <Super><Shift><letter>).
  moveWorkspaceBinds = lib.listToAttrs (
    map (
      n: lib.nameValuePair "move-to-workspace-${toString n}" [ "<Super><Shift>${toString n}" ]
    ) wsNumbers
  );
  # Free <Super>1…9 from GNOME's "activate Nth favourite app" shortcut.
  clearAppSwitchBinds = lib.listToAttrs (
    map (n: lib.nameValuePair "switch-to-application-${toString n}" [ ]) wsNumbers
  );

  autoMoveList = lib.mapAttrsToList (slot: v: "${v.app}:${slot}") appSlots;
  workspaceNames = [
    "Terminal"
    "Emacs"
    "Firefox"
    "Files"
  ]
  ++ map toString (lib.range 5 workspaceCount);

  large-text-toggler = pkgs.writeShellScriptBin "large-text-toggler" ''
    #!/usr/bin/env bash
    local scaling_factor="$(gsettings get org.gnome.desktop.interface text-scaling-factor)"
    local new_scaling_factor;
    if [[ "$scaling_factor" == "1.25" ]]; then
        new_scaling_factor="1.0";
    else
        new_scaling_factor="1.25";
    fi
    gsettings set org.gnome.desktop.interface text-scaling-factor "$new_scaling_factor";
  '';

  dark-light-theme-toggler = pkgs.writeShellScriptBin "dark-light-theme-toggler" ''
    #!/usr/bin/env bash
    local current_preference="$(gsettings get org.gnome.desktop.interface color-scheme)"
    local new_preference;
    if [[ "$current_preference" =~ dark ]]; then
        new_preference="prefer-light";
    else
        new_preference="prefer-dark";
    fi
    gsettings set org.gnome.desktop.interface color-scheme "$new_preference";
  '';
in
{
  home.packages = gnome-extensions ++ [
    pkgs.touchegg
    pkgs.libnotify # To get a newer version of notify-send which supports the --print-id flag
  ];

  systemd.user.services.touchegg = {
    Unit = {
      Description = "Touchegg Daemon";
      After = [ "default.target" ];
    };

    Service = {
      ExecStart = "${pkgs.touchegg}/bin/touchegg --daemon";
      Type = "simple";
      Restart = "on-failure";
    };

    Install.WantedBy = [ "multi-user.target" ];
  };

  services.gpg-agent.pinentry.package = pkgs.pinentry-gnome3;

  programs.gnome-shell = {
    enable = lib.mkDefault true;
    extensions = map (x: {
      id = x.extensionUuid;
      package = x;
    }) gnome-extensions;
  };

  # NOTE `dconf dump /` and `dconf watch /` are useful commands to see what's available.
  # See:
  #   - https://heywoodlh.io/nixos-gnome-settings-and-keyboard-shortcuts
  #   - https://hoverbear.org/blog/declarative-gnome-configuration-in-nixos/
  dconf.settings = {

    "org/gnome/shell" = {
      disable-user-extensions = false;
      disabled-extensions = [ ]; # TODO somehow the extensions auto-disable sometimes? this prevents it

      # `gnome-extensions list` for a list
      enabled-extensions = map (x: x.extensionUuid) gnome-extensions;
    };

    # Hide the sidebar dock menu
    "org/gnome/shell/extensions/dash-to-dock" = {
      dock-fixed = false;
    };

    # Unite extension settings
    "org/gnome/shell/extensions/unite" = {
      restrict-to-primary-screen = false;
      notifications-position = "center";
      show-window-buttons = "never";
      extend-left-box = false;
      autofocus-windows = true;
      hide-activities-button = "auto";
      hide-app-menu-icon = true;
      reduce-panel-spacing = false;
    };

    # Forge tiling extension — behaviour
    "org/gnome/shell/extensions/forge" = {
      tiling-mode-enabled = true;
      focus-border-toggle = true;
      window-gap-size = lib.gvariant.mkUint32 4;
      window-gap-hidden-on-single = true;
      auto-split-enabled = true;
      preview-hint-enabled = true;
      quick-settings-enabled = true;
    };

    # Forge keybindings — directions mirror the Hyprland config's rotated vim
    # scheme (h=up, j=left, k=down, l=right) so muscle memory carries over.
    # See nix/modules/home-manager/hyprland (movewindow binds).
    "org/gnome/shell/extensions/forge/keybindings" = {
      window-focus-up = [ "<Super>h" ];
      window-focus-left = [ "<Super>j" ];
      window-focus-down = [ "<Super>k" ];
      window-focus-right = [ "<Super>l" ];

      window-move-up = [ "<Shift><Super>h" ];
      window-move-left = [ "<Shift><Super>j" ];
      window-move-down = [ "<Shift><Super>k" ];
      window-move-right = [ "<Shift><Super>l" ];

      window-swap-up = [ "<Ctrl><Super>h" ];
      window-swap-left = [ "<Ctrl><Super>j" ];
      window-swap-down = [ "<Ctrl><Super>k" ];
      window-swap-right = [ "<Ctrl><Super>l" ];

      # Moved off the <Super>Period default so that key can drive the Files
      # workspace (matching Hyprland's "SUPER, period" → files workspace).
      prefs-open = [ "<Ctrl><Super>comma" ];
    };

    # Pin apps to workspaces — the Hyprland windowrule (class → workspace)
    # equivalent. Format is "<desktop-id>:<workspace-number>".
    "org/gnome/shell/extensions/auto-move-windows" = {
      application-list = autoMoveList;
    };

    # See: https://nixos.wiki/wiki/Virt-manager
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };

    # Multitasking — fixed (not dynamic) workspaces so app pinning and the
    # numbered/letter switch keys map onto stable slots (i3/Hyprland style).
    "org/gnome/mutter" = {
      workspaces-only-on-primary = false;
      experimental-features = [ "scale-monitor-framebuffer" ];
      dynamic-workspaces = false;
    };

    "org/gnome/desktop/wm/preferences" = {
      num-workspaces = workspaceCount;
      # Display names for the pinned slots; visibility depends on a workspace
      # indicator (e.g. the switcher popup) — switching is still by index.
      workspace-names = workspaceNames;
    };

    # Free <Super>1…9 (GNOME's "activate Nth favourite app") for workspaces.
    "org/gnome/shell/keybindings" = clearAppSwitchBinds;

    # Apparence > Dark
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      font-hinting = "slight";
      font-antialiasing = "rgba";
      clock-show-seconds = false;
      clock-show-weekday = true;
      accent-color = profile.gnomeAccentColor;

      # NOTE Downstream configurations might want to override these
      font-name = lib.mkDefault "Overpass 11";
      document-font-name = lib.mkDefault "Overpass Light 11";
      monospace-font-name = lib.mkDefault "JetBrains Mono 13";
      titlebar-font = lib.mkDefault "Overpass Bold 11";
    };

    "org/gnome/settings-daemon/plugins/color" = {
      night-light-enabled = true;
      night-light-temperature = 2700;
      night-light-last-coordinates = mkTuple [
        20.668991
        (-103.331455)
      ]; # TODO move to sensitive values?
    };

    "org/gnome/settings-daemon/plugins/color" = {
      power-button-action = "suspend";
      sleep-inactive-ac-type = "nothing";
      sleep-inactive-ac-timeout = 3600;
      sleep-inactive-battery-timeout = 900;
    };

    # TODO there's also "org/gnome/desktop/screensaver"
    "org/gnome/desktop/background" = {
      picture-uri = "file://${profile.wallpaper}";
      picture-uri-dark = "file://${profile.wallpaper}";
    };

    "org/gnome/desktop/peripherals/mouse" = {
      natural-scroll = true;
      speed = -0.5;
    };

    "org/gnome/desktop/peripherals/touchpad" = {
      natural-scroll = true;
      tap-to-click = true;
      two-finger-scrolling-enabled = true;
    };

    # Gnome keyboard layout
    "org/gnome/desktop/input-sources" = {
      show-all-sources = true;
      per-window = false;
      sources = [
        (mkTuple [
          "xkb"
          "us+colemak"
        ])
      ];
      xkb-options = [ "ctrl:nocaps" ];
    };

    # Gnome default keybindings
    "org/gnome/desktop/wm/keybindings" = {
      switch-applications = [ "<Super>Tab" ];
      switch-applications-backward = [ "<Shift><Super>Tab" ];
      switch-windows = [ "<Alt>Tab" ];
      switch-windows-backward = [ "<Shift><Alt>Tab" ];

      # Freed for Forge: <Super>h focuses up (GNOME default = minimize).
      minimize = [ ];
    }
    # <Super>N (+ app letter) to switch, <Super><Shift>N to move — see appSlots.
    // switchWorkspaceBinds
    // moveWorkspaceBinds;

    "org/freedesktop/ibus/panel/emoji" = {
      hotkey = "@as []";
    };

    # Gnome custom keybindings
    "org/gnome/settings-daemon/plugins/media-keys" = {
      terminal = [ ]; # Disables "Terminal Launcher" which opens gnome-terminal instead of Alacritty

      # Freed for Forge: <Super>l focuses right (GNOME default = lock screen).
      # Lock is still available via the power menu / suspend-on-lid.
      screensaver = [ ];

      # NOTE For every custom shortcut added the "path" to that shortcut must be added to this list
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom4/"
      ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "WezTerm";
      command = "wezterm";
      binding = "<Ctrl><Alt>t";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1" = {
      name = "Firefox";
      command = "firefox";
      binding = "<Ctrl><Alt>f";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2" = {
      name = "Emacs";
      command = "emacs";
      binding = "<Ctrl><Alt>e";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3" = {
      name = "Large Text Toggler";
      command = "${large-text-toggler}/bin/large-text-toggler";
      binding = "<Ctrl><Alt>l";
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom4" = {
      name = "Dark Light Theme Toggler";
      command = "${dark-light-theme-toggler}/bin/dark-light-theme-toggler";
      binding = "<Ctrl><Alt>.";
    };
  };
}
