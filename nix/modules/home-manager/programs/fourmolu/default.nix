{
  config,
  lib,
  ...
}:

# NOTE Fourmolu is part of the Haskell Toolchain overlay no need to install it separately

{
  xdg.configFile.fourmolu = {
    enable = lib.mkDefault true;
    source = ./fourmolu.yaml;
    target = "${config.xdg.configHome}/fourmolu/fourmolu.yaml";
  };
}
