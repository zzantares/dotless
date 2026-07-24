{
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./sddm.nix
  ];

  # NixOS Hyprland module handles XDG portals and environment setup automatically
  programs.hyprland.enable = lib.mkDefault true;

  # xdg-desktop-portal-gtk ships with UseIn=gnome in its .portal descriptor, so
  # xdg-desktop-portal ignores it in a Hyprland session by default. That means
  # no Settings portal → GTK4/libadwaita apps (Nautilus, etc.) get no color-scheme
  # response and fall back to light mode despite the dconf setting.
  # Explicitly route all unhandled interfaces to gtk so the Settings portal works.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.hyprland = {
    default = [
      "hyprland"
      "gtk"
    ];
  };

  # SDDM on Wayland as display manager
  services.displayManager.sddm.enable = lib.mkDefault true;
  services.displayManager.sddm.wayland.enable = lib.mkDefault true;
  # Force SDDM to use hyprland.desktop (Exec=Hyprland, blocking) instead of
  # hyprland-uwsm.desktop (Exec=uwsm start -e, non-blocking). The uwsm variant
  # exits after ~6 seconds once it has queued systemd units, causing SDDM to
  # close the PAM session before Hyprland ever starts → immediate black screen.
  services.displayManager.defaultSession = lib.mkDefault "hyprland";

  # Electron/Chromium apps on Wayland
  environment.sessionVariables.NIXOS_OZONE_WL = lib.mkDefault "1";

  # Location for night light / geoclue-aware apps
  services.geoclue2.enable = lib.mkDefault true;
  services.geoclue2.geoProviderUrl = "https://api.beacondb.net/v1/geolocate";

  # Keyring daemon for the libsecret API — used by browsers, NetworkManager,
  # and similar apps to store credentials. PAM integration auto-unlocks the
  # keyring on login so it's transparent to the user. The SSH agent component
  # caches SSH key passphrases in the keyring (persistent across reboots).
  services.gnome.gnome-keyring.enable = true;
  # Auto-unlock the keyring when the user authenticates at the SDDM login screen.
  security.pam.services.sddm.enableGnomeKeyring = true;

  # Touchpad
  services.libinput.enable = lib.mkDefault true;
  services.libinput.touchpad.tapping = lib.mkDefault true;
  services.libinput.touchpad.naturalScrolling = lib.mkDefault true;
  services.libinput.touchpad.disableWhileTyping = lib.mkDefault true;
  services.libinput.touchpad.accelSpeed = "0.6";
  services.libinput.mouse.naturalScrolling = lib.mkDefault true;

  # Prevents hyprland-uwsm.desktop (non-blocking Exec=uwsm start -e) from being
  # created; only hyprland.desktop (blocking Exec=Hyprland) remains, so SDDM
  # keeps the PAM session open for the full desktop lifetime.
  programs.hyprland.withUWSM = lib.mkDefault false;

  # NixOS sets SSH_ASKPASS to x11-ssh-askpass by default, which shows a GTK1
  # dialog. Override with seahorse's GNOME-native askpass so SSH key passphrase
  # prompts (e.g. from ssh-add during git commit signing) look consistent with
  # the rest of the desktop.
  programs.ssh.askPassword = lib.mkForce "${pkgs.seahorse}/libexec/seahorse/ssh-askpass";

  # File manager: Nautilus with gvfs for trash and volume mounting.
  environment.systemPackages = [ pkgs.nautilus ];
  services.gvfs.enable = lib.mkDefault true;

  # Bluetooth GUI — enables the D-Bus mechanism service needed for pairing.
  services.blueman.enable = lib.mkDefault true;

  # Lid close behavior: always suspend, whether on battery or AC.
  # Exception: when docked (external monitor connected), closing the lid
  # should keep the session running on the external display.
  # hypridle catches PrepareForSleep and runs hyprlock before suspend.
  services.logind.settings.Login = {
    HandleLidSwitch = lib.mkDefault "suspend";
    HandleLidSwitchExternalPower = lib.mkDefault "suspend";
    HandleLidSwitchDocked = lib.mkDefault "ignore";
  };
}
