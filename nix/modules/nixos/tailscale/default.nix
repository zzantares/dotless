{ lib, pkgs, ... }:

{
  services.tailscale = {
    enable = lib.mkDefault true;
    package = pkgs.tailscale;
    openFirewall = lib.mkDefault true;
  };
}
