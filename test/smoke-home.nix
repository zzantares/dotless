# Instantiate the home preset chain (workstation) so its modules' warnings
# surface under abort-on-warn.
{
  inputs,
  self,
  pkgs,
}:

let
  # presets reference inputs.dotless / inputs.self; here dotless is self.
  ciInputs = inputs // {
    dotless = self;
  };
  profile = import ./profile.nix;
in
(inputs.home-manager.lib.homeManagerConfiguration {
  inherit pkgs;

  extraSpecialArgs = {
    inputs = ciInputs;
    inherit profile;
  };

  modules = [
    self.homeModules.workstation
    (
      { pkgs, lib, ... }:
      {
        home.username = "ci";
        home.homeDirectory = "/home/ci";
        home.stateVersion = "24.05";

        # overlay package no preset installs — check it transitively here.
        # (zed-editor excluded: upstream zed flake warns on stdenv.isLinux.)
        home.packages = [ pkgs.linear-cli ];

        # dotless has no secrets/; stub the sops preset's defaultSopsFile.
        sops.validateSopsFiles = false;
        sops.defaultSopsFile = lib.mkForce (builtins.toFile "ci-dummy-secrets.yaml" "{}\n");
      }
    )
  ];
}).activationPackage
