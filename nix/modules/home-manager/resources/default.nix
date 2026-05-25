{
  config,
  lib,
  pkgs,
  profile,
  ...
}:

# Installs wallpapers, fonts, and icons into XDG data directories.
#
# dotless-provided content (wallpapers) comes from packages in the overlay —
# no `inputs.self` required, works transparently for downstream consumers.
#
# User-provided content is optional and configured via the `profile` attrset:
#   profile.fontsPath      — path to a directory of custom font files (.ttf/.otf)
#   profile.wallpapersPath — path to a directory of wallpaper images
#   profile.iconsPath      — path to a directory of icon themes
#
# Example in your flake:
#   profile.wallpapersPath = "${inputs.self}/resources/wallpapers";

{
  # dotless-provided wallpapers (sourced from the overlay — no inputs.self needed)
  xdg.dataFile.dotless-wallpapers = lib.mkIf (pkgs ? wallpapers) {
    enable = true;
    source = pkgs.wallpapers;
    target = "wallpapers/dotless";
  };

  # User-provided wallpapers
  xdg.dataFile.user-wallpapers = lib.mkIf ((profile ? wallpapersPath) && profile.wallpapersPath != null) {
    enable = true;
    source = profile.wallpapersPath;
    target = "wallpapers/user";
  };

  # User-provided custom fonts (set profile.fontsPath to a dir of .ttf/.otf files)
  # Note: nixpkgs-based fonts are handled via home.packages + fonts.fontconfig
  xdg.dataFile.user-fonts = lib.mkIf ((profile ? fontsPath) && profile.fontsPath != null) {
    enable = true;
    source = profile.fontsPath;
    target = "fonts/user";
    onChange = "${pkgs.fontconfig}/bin/fc-cache -f -v";
  };

  # User-provided icon themes
  xdg.dataFile.user-icons = lib.mkIf ((profile ? iconsPath) && profile.iconsPath != null) {
    enable = true;
    source = profile.iconsPath;
    target = "icons/user";
  };
}
