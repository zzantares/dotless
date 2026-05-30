{
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./../devstation
    ./../../../modules/home-manager/resources
    ./../../../modules/home-manager/programs/chrome
    ./../../../modules/home-manager/programs/firefox
    ./../../../modules/home-manager/programs/librewolf
    ./packages.nix
  ];

  home.shellAliases = {
    zed = "zeditor";
  };

  # Default applications
  xdg.configFile."mimeapps.list".force = true;
  xdg.mimeApps = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "text/html" = "firefox.desktop";
      "application/xhtml+xml" = "firefox.desktop";
    };
  };

}
