# CI-only smoke configs.
#
# The exported home/nixos/darwin modules are module *functions*, not
# derivations — their bodies (and any deprecation warnings inside them) only run
# once the module system instantiates them. These configs are the minimal
# harness that forces that evaluation, so a CI `nix eval <attr>.drvPath --option
# abort-on-warn true` fails on module/preset warnings at the source.
#
# Scoped to x86_64-linux by the flake (darwin eval on the Linux runner is
# cross-system and IFD-risky). Coverage is the two preset chains
# (base -> devstation -> workstation, base -> bare-metal -> desktop); à-la-carte
# modules outside those chains are not exercised yet.
{
  inputs,
  self,
  pkgs,
  system,
}:

{
  smoke-home = import ./smoke-home.nix { inherit inputs self pkgs; };
  smoke-nixos = import ./smoke-nixos.nix { inherit inputs self system; };
}
