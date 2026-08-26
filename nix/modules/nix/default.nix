theInputs@{
  inputs,
  profile,
  pkgs,
  lib,
  ...
}:

{
  # The dotless overlay is injected by the shared modules/nixpkgs module, imported
  # here so standalone home-manager configs (which reach the overlay only through
  # this module) still get it. Keeping it in one place means it is applied once
  # even when a config also pulls in a base preset. See modules/nixpkgs.
  imports = [ ./../nixpkgs ];

  # TODO later do this via a whitelist
  nixpkgs.config.allowUnfree = true;

  nix = {
    # In a multi-user installation Nix is at the system level which means
    # it can't be configured declaratively via home-manager on non NixOS
    # the `osConfig` attr set is available when using HM as a NixOS module
    enable = !(lib.hasAttr "osConfig" theInputs);
    package = pkgs.nix; # From the overlay

    registry = {
      nixpkgs.flake = inputs.nixpkgs;
    };

    nixPath = [
      "nixpkgs=${inputs.nixpkgs}"
    ];

    settings = {
      experimental-features = "nix-command flakes";

      trusted-users = [ profile.login ];

      # Deduplicate derivation outputs if they are the same
      # see: https://discourse.nixos.org/t/very-large-update-download-is-that-normal/31086/3
      auto-optimise-store = true;

      # Temporary solution to faster downloads see: https://github.com/NixOS/nix/issues/11728
      download-buffer-size = "524288000";

      substituters = [
        "https://cache.iog.io"
        "https://cache.nixos.org"
        "https://ghc-nix.cachix.org"
        "https://haskell-language-server.cachix.org"
        "https://iohk.cachix.org"
        "https://nix-community.cachix.org"
      ];

      trusted-public-keys = [
        "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" # for cache.iog.io
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "ghc-nix.cachix.org-1:ziC/I4BPqeA4VbtOFpFpu6D1t6ymFvRWke/lc2+qjcg="
        "haskell-language-server.cachix.org-1:juFfHrwkOxqIOZShtC4YC1uT1bBcq2RSvC7OMKx0Nz8="
        "iohk.cachix.org-1:DpRUyj7h7V830dp/i6Nti+NEO2/nhblbov/8MW7Rqoo="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };
}
