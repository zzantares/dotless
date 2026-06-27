{
  config,
  lib,
  pkgs,
  ...
}:

{
  programs.wezterm = {
    enable = lib.mkDefault true;
    package = if pkgs.stdenv.isDarwin then pkgs.wezterm else config.lib.nixGL.wrap pkgs.wezterm;

    enableZshIntegration = lib.mkDefault true;
  };
}
