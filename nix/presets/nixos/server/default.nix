{ ... }:

# A server is a bare-metal machine acting as a network node —
# no desktop session, no wireless, reachable only over the network.

{
  imports = [
    ./../bare-metal
    ./../node
  ];

  networking.wireless.enable = false;
  networking.wireless.iwd.enable = false;

  services.resolved.enable = true;
}
