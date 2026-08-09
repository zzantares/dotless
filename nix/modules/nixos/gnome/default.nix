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

  # SSH agent: GNOME ships its own (gcr-ssh-agent, part of gnome-keyring) and it
  # owns SSH_AUTH_SOCK in the session. Don't also run gpg-agent as an SSH agent -
  # two agents racing for SSH_AUTH_SOCK is a latent conflict that only ever
  # confuses things. gpg-agent stays enabled for GPG; it just isn't the SSH one.
  programs.gnupg.agent.enableSSHSupport = lib.mkForce false;

  # gcr-ssh-agent is socket-activated at sockets.target (early boot), before the
  # GNOME session exports DISPLAY/WAYLAND into the systemd --user environment.
  # Its passphrase prompt (gcr4-ssh-askpass) is a GUI dialog, so without those
  # vars it cannot render and any operation that must unlock a passphrase-
  # protected key (e.g. SSH-format git commit signing) hangs forever with no
  # visible prompt. Tie the agent's start to the graphical session so it only
  # comes up after that environment exists.
  systemd.user.services.gcr-ssh-agent = {
    overrideStrategy = "asDropin";
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    # Only the graphical session may pull the agent up - not default.target
    # (early boot), which would reintroduce the start-before-DISPLAY race. The
    # socket (wantedBy sockets.target) still sets SSH_AUTH_SOCK early and queues
    # connections until the service starts.
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
