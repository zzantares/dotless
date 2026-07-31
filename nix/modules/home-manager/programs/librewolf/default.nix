{
  config,
  profile,
  pkgs,
  lib,
  ...
}:

let

  browserConfig = import ../browser {
    inherit
      profile
      config
      lib
      pkgs
      ;
  };

in

{
  programs.librewolf = lib.attrsets.recursiveUpdate browserConfig {
    # LibreWolf's nixpkgs wrapper force-sets MOZ_LEGACY_PROFILES=1 via makeWrapper
    # `--set`, which can't be overridden at the home-manager level, so the browser
    # always reads its profile from ~/.librewolf regardless of XDG_CONFIG_HOME.
    # This matches home-manager's own default for programs.librewolf, spelled out
    # explicitly rather than left implicit.
    configPath = "${config.home.homeDirectory}/.librewolf";
  };
}
