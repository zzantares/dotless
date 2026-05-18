{
  lib,
  pkgs,
  profile,
  ...
}:

let
  # Analogous to dark-light-theme-toggler in gnome/default.nix
  dark-light-theme-toggler = pkgs.writeShellScriptBin "dark-light-theme-toggler" ''
    #!/usr/bin/env bash
    current="$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)"
    if [[ "$current" == *"Dark"* ]]; then
      plasma-apply-colorscheme BreezeClassic
      plasma-apply-lookandfeel --apply org.kde.breeze.desktop
    else
      plasma-apply-colorscheme BreezeDark
      plasma-apply-lookandfeel --apply org.kde.breezedark.desktop
    fi
  '';

  # Analogous to large-text-toggler in gnome/default.nix
  # Toggles the forced font DPI between default (96) and ~1.25x (120)
  large-text-toggler = pkgs.writeShellScriptBin "large-text-toggler" ''
    #!/usr/bin/env bash
    current="$(kreadconfig6 --file kdeglobals --group General --key XftDpi --default 0)"
    if [[ "$current" == "120" ]]; then
      kwriteconfig6 --file kdeglobals --group General --key XftDpi 0
    else
      kwriteconfig6 --file kdeglobals --group General --key XftDpi 120
    fi
    dbus-send --session --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true
  '';

  plasma-browser-integration = pkgs.nur.repos.rycee.firefox-addons.buildFirefoxXpiAddon {
    pname = "plasma-browser-integration";
    version = "2.1";
    addonId = "plasma-browser-integration@kde.org";
    url = "https://addons.mozilla.org/firefox/downloads/file/4614817/plasma_integration-2.1.xpi";
    sha256 = "sha256-Nb+jdm4JcWDnT1Jb3lTZe7upDXJdqkJbneb+9uxenUQ=";
    meta.license = lib.licenses.gpl3Only;
  };
in
{
  home.packages = [
    pkgs.libnotify
    pkgs.kdePackages.ksshaskpass
    large-text-toggler
    dark-light-theme-toggler
  ];

  # Enable SSH agent (overrides lib.mkDefault false in the SSH module, which defers to GNOME Keyring)
  services.ssh-agent.enable = true;

  # Use ksshaskpass for graphical SSH passphrase prompts (analogous to GNOME Keyring handling SSH on GNOME)
  home.sessionVariables = {
    SSH_ASKPASS = "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
    SSH_ASKPASS_REQUIRE = "prefer";
  };

  # Qt pinentry for KDE (analogous to pinentry-gnome3 in gnome/default.nix)
  services.gpg-agent.pinentry.package = lib.mkForce pkgs.pinentry-qt;

  # NOTE `plasma-apply-colorscheme --list-schemes` and `kreadconfig6` are useful for inspecting state.
  # See:
  #   - https://github.com/nix-community/plasma-manager
  #   - https://develop.kde.org/docs/plasma/scripting/
  programs.plasma = {
    enable = true;

    workspace = {
      # Analogous to color-scheme = "prefer-dark"
      colorScheme = "BreezeDark";
      lookAndFeel = "org.kde.breezedark.desktop";

      # Analogous to org/gnome/desktop/background picture-uri
      wallpaper = "${profile.wallpaper}";
    };

    # NOTE downstream configurations might want to override these
    fonts = {
      general = {
        family = lib.mkDefault "Overpass";
        pointSize = lib.mkDefault 11;
      };
      fixedWidth = {
        family = lib.mkDefault "JetBrains Mono";
        pointSize = lib.mkDefault 13;
      };
      small = {
        family = lib.mkDefault "Overpass";
        pointSize = lib.mkDefault 8;
      };
      toolbar = {
        family = lib.mkDefault "Overpass";
        pointSize = lib.mkDefault 11;
      };
      menu = {
        family = lib.mkDefault "Overpass";
        pointSize = lib.mkDefault 11;
      };
      windowTitle = {
        family = lib.mkDefault "Overpass";
        pointSize = lib.mkDefault 11;
      };
    };

    # Analogous to org/gnome/settings-daemon/plugins/color night-light-* settings
    # NOTE: redshift is disabled in the NixOS KDE module to avoid conflict with this
    kwin.virtualDesktops = {
      number = 3;
      rows = 1;
    };

    kwin.nightLight = {
      enable = true;
      mode = "location";
      location = {
        latitude = "20.668991";
        longitude = "-103.331455";
      };
      temperature.night = 2700;
    };

    # Analogous to org/gnome/settings-daemon/plugins/power-* settings
    powerdevil = {
      AC = {
        powerButtonAction = "sleep"; # Analogous to power-button-action = "suspend"
        autoSuspend.action = "nothing"; # Analogous to sleep-inactive-ac-type = "nothing"
        turnOffDisplay.idleTimeout = 3600;
      };
      battery = {
        powerButtonAction = "sleep";
        autoSuspend = {
          action = "sleep";
          idleTimeout = 900; # Analogous to sleep-inactive-battery-timeout
        };
      };
    };

    # Analogous to org/gnome/desktop/wm/keybindings switch-windows/switch-applications
    shortcuts = {
      "kwin"."Walk Through Windows" = "Alt+Tab";
      "kwin"."Walk Through Windows (Reverse)" = "Shift+Alt+Tab";
      "kwin"."Walk Through Windows of Current Application" = "Meta+Tab";
      "kwin"."Walk Through Windows of Current Application (Reverse)" = "Shift+Meta+Tab";
    };

    # Analogous to org/gnome/settings-daemon/plugins/media-keys custom-keybindings
    panels = [
      {
        location = "bottom";
        height = 32;
        hiding = "windowscover";
        widgets = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.icontasks"
          "org.kde.plasma.marginsseparator"
          "org.kde.plasma.systemtray"
          "org.kde.plasma.digitalclock"
          "org.kde.plasma.showdesktop"
        ];
      }
    ];

    hotkeys.commands = {
      "launch-alacritty" = {
        name = "Alacritty";
        key = "Ctrl+Alt+T";
        command = "alacritty";
      };
      "launch-firefox" = {
        name = "Firefox";
        key = "Ctrl+Alt+F";
        command = "firefox";
      };
      "launch-emacs" = {
        name = "Emacs";
        key = "Ctrl+Alt+E";
        command = "emacs";
      };
      "toggle-large-text" = {
        name = "Large Text Toggler";
        key = "Ctrl+Alt+L";
        command = "${large-text-toggler}/bin/large-text-toggler";
      };
      "toggle-dark-light" = {
        name = "Dark Light Theme Toggler";
        key = "Ctrl+Alt+.";
        command = "${dark-light-theme-toggler}/bin/dark-light-theme-toggler";
      };
    };
  };

  # Plasma Browser Integration extension (native host already provided by services.desktopManager.plasma6)
  programs.librewolf.profiles."${profile.login}".extensions.packages = [ plasma-browser-integration ];

  # virt-manager uses GSettings/dconf regardless of desktop environment
  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };
  };
}
