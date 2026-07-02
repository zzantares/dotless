{
  lib,
  ...
}:

{
  services.desktopManager.cosmic.enable = lib.mkDefault true;
  services.displayManager.cosmic-greeter.enable = lib.mkDefault true;

  # Location for COSMIC's built-in night light
  services.geoclue2.enable = lib.mkDefault true;
  services.geoclue2.geoProviderUrl = "https://api.beacondb.net/v1/geolocate";

  # Enable touchpad support
  services.libinput.enable = lib.mkDefault true;
  services.libinput.touchpad.tapping = lib.mkDefault true;
  services.libinput.touchpad.naturalScrolling = lib.mkDefault true;
  services.libinput.touchpad.disableWhileTyping = lib.mkDefault true;
  services.libinput.touchpad.accelSpeed = "0.6";
  services.libinput.mouse.naturalScrolling = lib.mkDefault true;
}
