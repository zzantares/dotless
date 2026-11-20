# CI smoke configs: instantiate the presets so module warnings surface under
# abort-on-warn. x86_64-linux only (wired in flake.nix).
{
  inputs,
  self,
  pkgs,
  system,
}:

{
  appearance-darwin = import ./appearance-darwin.nix { inherit inputs self pkgs; };
  appearance-fallbacks = import ./appearance-fallbacks.nix { inherit inputs self pkgs; };
  appearance-provider = import ./appearance-provider.nix { inherit inputs self pkgs; };
  smoke-home = import ./smoke-home.nix { inherit inputs self pkgs; };
  smoke-nixos = import ./smoke-nixos.nix { inherit inputs self system; };
  zed-compose = import ./zed-compose.nix { inherit inputs self pkgs; };
}
