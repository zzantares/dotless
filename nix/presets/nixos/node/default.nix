{
  profile,
  lib,
  ...
}:

# Nodes are machines used primarily for compute (cattle, not pets).
# Uses systemd-networkd instead of NetworkManager for leaner network management.
# Auto-upgrade is enabled when profile.flakeUrl is set.

{
  networking.networkmanager.enable = false;
  networking.useNetworkd = true;
  systemd.network.enable = true;
  services.resolved.enable = true;

  system.autoUpgrade = lib.mkIf (profile ? flakeUrl) {
    enable = true;
    operation = "switch";
    flake = profile.flakeUrl;
  };
}
