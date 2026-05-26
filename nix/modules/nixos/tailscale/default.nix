{ pkgs, ... }:

{
  services.tailscale = {
    enable = lib.mkDefault true;
    package = pkgs.tailscale;
    openFirewall = true;
  };
}
