{
  profile,
  config,
  lib,
  pkgs,
  ...
}:

# This is the place to put some minimal configuration that makes sense for
# all managed systems even for those that do not have a GUI set up like a
# server only accessible through the network, therefore settings that touch
# on desktop sessions, resolution, icons, fonts, GUI applications, do not
# make sense to add here.
#
# Keep this minimal.

{
  imports = [
    ./../../../modules/home-manager/sops
    ./../../../modules/home-manager/programs/ssh
    ./packages.nix
  ];

  home.username = profile.login;

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.homeDirectory =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "/Users/${config.home.username}"
    else
      "/home/${config.home.username}";
  home.sessionVariables = {
    EDITOR = lib.mkDefault "nvim";
    COLORTERM = lib.mkDefault "truecolor";
    TERM = lib.mkDefault "xterm-256color";
  };

  xdg.enable = true;

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
