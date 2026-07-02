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

  # Touchpad
  services.libinput.enable = lib.mkDefault true;
  services.libinput.touchpad.tapping = lib.mkDefault true;
  services.libinput.touchpad.naturalScrolling = lib.mkDefault true;
  services.libinput.touchpad.disableWhileTyping = lib.mkDefault true;
  services.libinput.touchpad.accelSpeed = "0.6";
  services.libinput.mouse.naturalScrolling = lib.mkDefault true;
}
