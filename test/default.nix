# CI smoke configs: instantiate the presets so module warnings surface under
# abort-on-warn. x86_64-linux only (wired in flake.nix).
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
