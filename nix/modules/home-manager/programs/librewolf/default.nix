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
    configPath = "${config.xdg.configHome}/mozilla/librewolf";
  };
}
