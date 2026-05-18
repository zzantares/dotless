{
  ...
}:

{
  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.defaultSession = "gnome";
  services.xserver.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.gnome.gnome-settings-daemon.enable = true;
  programs.dconf.enable = true;

  # Warm screen light at night
  location.provider = "geoclue2";
  services.geoclue2.enable = true;
  services.geoclue2.geoProviderUrl = "https://api.beacondb.net/v1/geolocate";
  services.redshift = {
    enable = true;

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
  services.libinput.enable = true;
  services.libinput.touchpad.tapping = true;
  services.libinput.touchpad.naturalScrolling = true;
  services.libinput.touchpad.disableWhileTyping = true;
  services.libinput.touchpad.accelSpeed = "0.6";
}
