{
  config,
  lib,
  pkgs,
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

  # NOTE Other desirable stuff (though might not be only for KDE)
  # 2. Run SDDM itself on Wayland (currently it defaults to X11 even when the desktop session is Wayland)
  # services.displayManager.sddm.wayland.enable = true;

  # 3. KDE Connect (phone integration — also opens the required firewall ports automatically)
  # programs.kdeconnect.enable = true;

  # 4. Bluetooth
  # hardware.bluetooth.enable = true;
  # hardware.bluetooth.powerOnBoot = true;

  # 5. Power Profiles Daemon (KDE's PowerDevil integrates with this for battery/performance profiles — it's commented out in zephyrus/configuration.nix but should live here)
  # services.power-profiles-daemon.enable = true;

  # 6. Electron/Chromium apps on Wayland — otherwise apps like VS Code, Discord, etc. run via XWayland
  # environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
