{
  ...
}:

{
  # Enable the X11 windowing system.
  services.xserver.enable = lib.mkDefault true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.defaultSession = "gnome";
  services.xserver.displayManager.gdm.enable = lib.mkDefault true;
  services.desktopManager.gnome.enable = lib.mkDefault true;
  services.gnome.gnome-settings-daemon.enable = lib.mkDefault true;
  programs.dconf.enable = lib.mkDefault true;

  # Warm screen light at night
  location.provider = "geoclue2";
  services.geoclue2.enable = lib.mkDefault true;
  services.geoclue2.geoProviderUrl = "https://api.beacondb.net/v1/geolocate";
  services.redshift = {
    enable = lib.mkDefault true;

    brightness = {
      day = "1";
      night = "0.90";
    };

    temperature = {
      day = 6500;
      night = 2000;
    };
  };

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = lib.mkDefault true;
  services.libinput.touchpad.tapping = lib.mkDefault true;
  services.libinput.touchpad.naturalScrolling = lib.mkDefault true;
  services.libinput.touchpad.disableWhileTyping = lib.mkDefault true;
  services.libinput.touchpad.accelSpeed = "0.6";
}
