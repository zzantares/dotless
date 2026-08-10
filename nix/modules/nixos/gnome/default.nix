{
  lib,
  ...
}:

{
  # Enable the X11 windowing system.
  services.xserver.enable = lib.mkDefault true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.defaultSession = "gnome";
  services.displayManager.gdm.enable = lib.mkDefault true;
  services.desktopManager.gnome.enable = lib.mkDefault true;
  services.gnome.gnome-settings-daemon.enable = lib.mkDefault true;
  programs.dconf.enable = lib.mkDefault true;

  # gcr-ssh-agent is disabled: its ssh-add helper spins in a busy loop with
  # ED25519 keys (upstream gcr bug), accumulating runaway ssh-add processes at
  # 80-90% CPU. gpg-agent serves SSH instead (see the home-manager gnome module).
  # mkOverride 500 (stronger than mkDefault): nixpkgs' GNOME desktop module
  # enables it via mkDefault true, so a plain mkDefault false would conflict;
  # this beats that while staying overridable by a downstream plain value.
  services.gnome.gcr-ssh-agent.enable = lib.mkOverride 500 false;

  # The ordering fix below is kept inert for anyone who re-enables gcr-ssh-agent:
  # gcr-ssh-agent starts early (sockets.target), before GNOME exports
  # DISPLAY/WAYLAND, so its GUI askpass can't render and unlocking a passphrase-
  # protected key (e.g. SSH commit signing) hangs. Start it after the graphical
  # session so that environment exists.
  systemd.user.services.gcr-ssh-agent = {
    overrideStrategy = "asDropin";
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    # mkForce: the packaged unit sets `WantedBy=default.target` at normal
    # priority; only a force replaces it so the graphical session alone starts it.
    wantedBy = lib.mkForce [ "graphical-session.target" ];
  };

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
