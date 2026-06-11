{
  lib,
  ...
}:

{
  # Run SDDM itself on Wayland (currently it defaults to X11 even when the desktop session is Wayland)
  services.displayManager.sddm.wayland.enable = lib.mkDefault true;

  # Electron/Chromium apps on Wayland — otherwise apps like VS Code, Discord, etc. run via XWayland
  environment.sessionVariables.NIXOS_OZONE_WL = lib.mkDefault "1";
}
