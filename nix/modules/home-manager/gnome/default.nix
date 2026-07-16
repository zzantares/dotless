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
    tiling-shell
    unite
    x11-gestures
  ];

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

    # See: https://nixos.wiki/wiki/Virt-manager
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };

    # Multitasking
    "org/gnome/mutter" = {
      workspaces-only-on-primary = false;
      experimental-features = [ "scale-monitor-framebuffer" ];
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
      switch-applications-backward = [ "<Shift><Super>Tab" ];
      switch-windows = [ "<Alt>Tab" ];
      switch-windows-backward = [ "<Shift><Alt>Tab" ];
    };

    "org/freedesktop/ibus/panel/emoji" = {
      hotkey = "@as []";
    };

    # Gnome custom keybindings
    "org/gnome/settings-daemon/plugins/media-keys" = {
      terminal = [ ]; # Disables "Terminal Launcher" which opens gnome-terminal instead of Alacritty

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
