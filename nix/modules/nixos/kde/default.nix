{
  lib,
  ...
}:

{
  services.displayManager.sddm.enable = lib.mkDefault true;
  services.desktopManager.plasma6.enable = lib.mkDefault true;

  # Night light is handled by KWin (configured via plasma-manager in the HM KDE module).
  # geoclue2 is kept for KDE's automatic location mode if ever needed.
  services.geoclue2.enable = lib.mkDefault true;
  services.geoclue2.geoProviderUrl = "https://api.beacondb.net/v1/geolocate";

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = lib.mkDefault true;
  services.libinput.touchpad.tapping = lib.mkDefault true;
  services.libinput.touchpad.naturalScrolling = lib.mkDefault true;
  services.libinput.touchpad.disableWhileTyping = lib.mkDefault true;
  services.libinput.touchpad.accelSpeed = "0.6";
  services.libinput.mouse.naturalScrolling = lib.mkDefault true;

  # KDE Connect (phone integration — also opens the required firewall ports automatically)
  # programs.kdeconnect.enable = true;
}
