{ lib, ... }:

# NOTE Fourmolu is part of the Haskell Toolchain overlay no need to install it separately

# Fourmolu only auto-discovers `fourmolu.yaml' in the parents of the source
# file and then in $XDG_CONFIG_HOME itself, never in a `fourmolu/' subdir.

{
  xdg.configFile."fourmolu.yaml" = {
    enable = lib.mkDefault true;
    source = ./fourmolu.yaml;
  };
}
