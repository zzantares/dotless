# Smoke-eval the home preset chain (base -> devstation -> workstation), which
# transitively pulls in most home modules. Instantiating it forces the module
# bodies to run, so `abort-on-warn` in CI catches deprecation warnings at the
# source instead of only once a consumer builds a config.
{
  inputs,
  self,
  pkgs,
}:

let
  # Presets reference `inputs.dotless.*` and `inputs.self` from the consumer's
  # namespace; inside dotless itself, `dotless` is just `self`.
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
      { lib, ... }:
      {
        home.username = "ci";
        home.homeDirectory = "/home/ci";
        home.stateVersion = "24.05";

        # dotless ships no secrets/ dir, so the sops preset's defaultSopsFile
        # points at a path that does not exist. Stub it for the smoke eval.
        sops.validateSopsFiles = false;
        sops.defaultSopsFile = lib.mkForce (builtins.toFile "ci-dummy-secrets.yaml" "{}\n");
      }
    )
  ];
}).activationPackage
