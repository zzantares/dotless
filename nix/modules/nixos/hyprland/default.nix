{
  lib,
  ...
}:

{
  # NixOS Hyprland module handles XDG portals and environment setup automatically
  programs.hyprland.enable = lib.mkDefault true;

  # SDDM on Wayland as display manager
  services.displayManager.sddm.enable = lib.mkDefault true;
  services.displayManager.sddm.wayland.enable = lib.mkDefault true;

  # Electron/Chromium apps on Wayland
  environment.sessionVariables.NIXOS_OZONE_WL = lib.mkDefault "1";

  # Location for night light / geoclue-aware apps
  services.geoclue2.enable = lib.mkDefault true;
  services.geoclue2.geoProviderUrl = "https://api.beacondb.net/v1/geolocate";

  # Keyring daemon for the libsecret API — used by browsers, Element, Slack,
  # Protonmail Bridge, and similar apps to store credentials. PAM integration
  # auto-unlocks the keyring on login so it's transparent to the user.
  # NOTE: gnome-keyring also starts an SSH agent component; that component's
  # SSH_AUTH_SOCK is overridden in the HM hyprland module to ensure gpg-agent
  # handles all SSH operations instead.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # Touchpad
  services.libinput.enable = lib.mkDefault true;
  services.libinput.touchpad.tapping = lib.mkDefault true;
  services.libinput.touchpad.naturalScrolling = lib.mkDefault true;
  services.libinput.touchpad.disableWhileTyping = lib.mkDefault true;
  services.libinput.touchpad.accelSpeed = "0.6";
  services.libinput.mouse.naturalScrolling = lib.mkDefault true;
}
