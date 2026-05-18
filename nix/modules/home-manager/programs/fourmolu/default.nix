{
  config,
  ...
}:

# NOTE Fourmolu is part of the Haskell Toolchain overlay no need to install it separately

{
  xdg.configFile.fourmolu = {
    enable = true;
    source = ./fourmolu.yaml;
    target = "${config.xdg.configHome}/fourmolu/fourmolu.yaml";
  };
}
