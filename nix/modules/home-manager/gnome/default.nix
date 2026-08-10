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
    auto-move-windows-follow # Pin apps to workspaces + follow focus there (i3 `assign`, Hyprland-style follow)
    clipboard-indicator # Clipboard history (cliphist + wofi equivalent)
    unite
    x11-gestures
  ];

  # ── i3/Hyprland-style fixed workspaces ────────────────────────────────────
  # GNOME/Mutter has no named, on-demand workspaces like Hyprland; it only has
  # a fixed numbered list. We approximate the Hyprland app-workspaces (E/T/F/·)
  # by pinning each app to a fixed slot and giving that slot its Hyprland letter
  # as an extra switch accelerator, alongside the plain number.
  workspaceCount = 9;

  # Single source of truth per app, mirroring how Hyprland co-locates a
  # workspace, a windowrule, and an exec bind:
  #   key  = letter for the "<Super>+key" workspace switch/move accelerators
  #   app  = .desktop id to pin to this workspace (auto-move-windows)
  #   cmd  = command launched by <Ctrl><Super>+key (Hyprland "SUPER CTRL" bind)
  #   name = label for the launcher keybinding
  appSlots = {
    "1" = {
      key = "t";
      app = "Alacritty.desktop";
      cmd = "alacritty";
      name = "Alacritty";
    };
    "2" = {
      key = "e";
      app = "emacs.desktop";
      cmd = "emacsclient -c -a emacs";
      name = "Emacs";
    };
    "3" = {
      key = "f";
      app = "firefox.desktop";
      cmd = "firefox";
      name = "Firefox";
    };
    "4" = {
      key = "period";
      app = "org.gnome.Nautilus.desktop";
      cmd = "nautilus";
      name = "Files";
    };
  };

  wsNumbers = lib.genList (i: i + 1) workspaceCount; # [ 1 … 9 ]
  # The pinned slot's app letter, prefixed with the given modifier (or [ ]).
  slotKey = mods: n: lib.optional (appSlots ? ${toString n}) "${mods}${appSlots.${toString n}.key}";

  # Switch: <Super>N (+ the app letter for pinned slots).
  switchWorkspaceBinds = lib.listToAttrs (
    map (
      n:
      lib.nameValuePair "switch-to-workspace-${toString n}" (
        [ "<Super>${toString n}" ] ++ slotKey "<Super>" n
      )
    ) wsNumbers
  );
  # Move window to workspace: <Super><Shift>N (+ the app letter), mirroring the
  # Hyprland/AeroSpace "move to workspace" bind. Forge's tabbed-layout-toggle is
  # relocated off <Shift><Super>t below so the Terminal letter is free here.
  moveWorkspaceBinds = lib.listToAttrs (
    map (
      n:
      lib.nameValuePair "move-to-workspace-${toString n}" (
        [ "<Super><Shift>${toString n}" ] ++ slotKey "<Super><Shift>" n
      )
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

  # App launchers on <Ctrl><Super>+<letter>, mirroring Hyprland's "SUPER CTRL"
  # exec binds. Derived from appSlots so each app's workspace, pin, and launch
  # key all stay defined in one place.
  appLaunchers = lib.mapAttrsToList (_: v: {
    name = v.name;
    command = v.cmd;
    binding = "<Ctrl><Super>${v.key}";
  }) appSlots;
  # Non-app togglers keep their existing <Ctrl><Alt> binds.
  extraKeybindings = [
    {
      name = "Large Text Toggler";
      command = "${large-text-toggler}/bin/large-text-toggler";
      binding = "<Ctrl><Alt>l";
    }
    {
      name = "Dark Light Theme Toggler";
      command = "${dark-light-theme-toggler}/bin/dark-light-theme-toggler";
      binding = "<Ctrl><Alt>period";
    }
  ];
  # Materialise as customN entries + the paths list GNOME expects to register.
  customKeybindings = appLaunchers ++ extraKeybindings;
  customKeybindingPaths = lib.imap0 (
    i: _: "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${toString i}/"
  ) customKeybindings;
  customKeybindingSettings = lib.listToAttrs (
    lib.imap0 (
      i: e:
      lib.nameValuePair "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom${toString i}" e
    ) customKeybindings
  );

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

  # gpg-agent serves SSH here: GNOME's gcr-ssh-agent is disabled (its ssh-add
  # helper busy-loops with ED25519 keys), so gpg-agent owns SSH_AUTH_SOCK.
  # pinentry-gnome3 gives both GPG and the SSH key unlock a native GNOME prompt.
  services.gpg-agent = {
    enableSshSupport = lib.mkDefault true;
    # Stronger default (mkOverride 500, between normal=100 and mkDefault=1000):
    # overrides the devstation preset's `mkDefault pinentry-curses` while staying
    # overridable by a downstream plain value without a conflict.
    pinentry.package = lib.mkOverride 500 pkgs.pinentry-gnome3;
  };

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
      window-gap-size = lib.gvariant.mkUint32 4;
      window-gap-hidden-on-single = true;
      auto-split-enabled = true;
      preview-hint-enabled = true;
      quick-settings-enabled = true;

      # Focus indicator — a thin white-ish border on the focused window, like
      # Hyprland (border_size = 2). Disable the extra split-direction border so
      # there's a single, clean focus border.
      focus-border-toggle = true;
      focus-border-size = lib.gvariant.mkUint32 1;
      focus-border-color = "rgba(235, 235, 235, 0.9)";
      split-border-toggle = false;
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

      # Relocated to <Ctrl><Super>Tab (mnemonic: Tab → tabbed) so <Shift><Super>t
      # is free to move a window to the Terminal workspace and <Ctrl><Super>t is
      # free to launch the terminal.
      con-tabbed-layout-toggle = [ "<Ctrl><Super>Tab" ];
    };

    # Pin apps to workspaces — the Hyprland windowrule (class → workspace)
    # equivalent. Format is "<desktop-id>:<workspace-number>".
    "org/gnome/shell/extensions/auto-move-windows" = {
      application-list = autoMoveList;
    };

    # Clipboard history popup — mirrors Hyprland's cliphist + wofi bind.
    "org/gnome/shell/extensions/clipboard-indicator" = {
      enable-keybindings = true;
      toggle-menu = [ "<Ctrl><Super>v" ];
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

    # Free <Super>1…9 (GNOME's "activate Nth favourite app") for workspaces,
    # and put the app grid on <Super>space (Hyprland's launcher key) alongside
    # the default <Super>a.
    "org/gnome/shell/keybindings" = clearAppSwitchBinds // {
      toggle-application-view = [
        "<Super>a"
        "<Super>space"
      ];
    };

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
      # <Shift><Super>Tab is repurposed below (send window to external monitor);
      # the app switcher still reverses with Shift while its popup is open.
      switch-applications-backward = [ ];
      switch-windows = [ "<Alt>Tab" ];
      switch-windows-backward = [ "<Shift><Alt>Tab" ];

      # Freed for Forge: <Super>h focuses up (GNOME default = minimize).
      minimize = [ ];

      # Close focused window — mirror Hyprland's <Super><Shift>Backspace killactive
      # (keep the GNOME default <Alt>F4 too).
      close = [
        "<Alt>F4"
        "<Super><Shift>BackSpace"
      ];

      # Free <Super>space (default input-source switch) for the app launcher
      # below — single keyboard layout, so switching is unused.
      switch-input-source = [ ];

      # Send the focused window to the external display (on the left), mirroring
      # the Hyprland/AeroSpace <Super><Shift>Tab "to other monitor" bind. GNOME
      # moves a window, not a whole workspace, and only by direction — keep the
      # default <Super><Shift>Left too.
      move-to-monitor-left = [
        "<Super><Shift>Left"
        "<Shift><Super>Tab"
      ];
    }
    # <Super>N (+ app letter) to switch, <Super><Shift>N to move — see appSlots.
    // switchWorkspaceBinds
    // moveWorkspaceBinds;

    "org/freedesktop/ibus/panel/emoji" = {
      hotkey = "@as []";
    };

    # Gnome custom keybindings — app launchers (<Ctrl><Super>+letter, mirroring
    # Hyprland's SUPER CTRL exec binds) plus the theme/text togglers. The customN
    # entries themselves are merged in below from customKeybindingSettings.
    "org/gnome/settings-daemon/plugins/media-keys" = {
      terminal = [ ]; # Disables "Terminal Launcher" which opens gnome-terminal instead of Alacritty

      # Lock moved off <Super>l (now Forge focus-right) to <Super><Shift>Escape.
      screensaver = [ "<Super><Shift>Escape" ];

      custom-keybindings = customKeybindingPaths;
    };
  }
  // customKeybindingSettings;
}
