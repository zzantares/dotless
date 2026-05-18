{
  lib,
  ...
}:

let
  # True if a directory contains a specific file
  hasFile = dir: filename: builtins.pathExists (dir + "/${filename}");

  # Get all subdirectories names of a path (without the path portion)
  getSubdirs =
    dir:
    let
      contents = builtins.readDir dir;
      dirs = lib.filterAttrs (_name: type: type == "directory") contents;
    in
    lib.attrNames dirs;

  # Create an attrset mapping directory names to their imported default.nix with baseArgs applied
  discoverConfigs =
    dir: baseArgs: predicate:
    let
      subdirs = getSubdirs dir;
      matchingDirs = builtins.filter (name: predicate (dir + "/${name}")) subdirs;
    in
    lib.genAttrs matchingDirs (name: import (dir + "/${name}") baseArgs);

in
{
  # Discover NixOS configurations (directories containing configuration.nix)
  discoverNixos =
    dir: baseArgs: discoverConfigs dir baseArgs (subdir: hasFile subdir "configuration.nix");

  # Discover Home Manager configurations (directories containing home.nix but not configuration.nix)
  discoverHome =
    dir: baseArgs:
    discoverConfigs dir baseArgs (
      subdir: hasFile subdir "home.nix" && !(hasFile subdir "configuration.nix")
    );

  # Discover nix-darwin configurations (directories containing darwin.nix)
  discoverDarwin =
    dir: baseArgs: discoverConfigs dir baseArgs (subdir: hasFile subdir "darwin.nix");
}
