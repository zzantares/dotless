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
    enable = lib.mkDefault true;
    source = pkgs.wallpapers;
    target = "wallpapers/dotless";
  };

  # User-provided wallpapers
  xdg.dataFile.user-wallpapers =
    lib.mkIf ((profile ? wallpapersPath) && profile.wallpapersPath != null)
      {
        enable = lib.mkDefault true;
        source = profile.wallpapersPath;
        target = "wallpapers/user";
      };

  # User-provided custom fonts (set profile.fontsPath to a dir of .ttf/.otf files)
  # Note: nixpkgs-based fonts are handled via home.packages + fonts.fontconfig
  xdg.dataFile.user-fonts = lib.mkIf ((profile ? fontsPath) && profile.fontsPath != null) {
    enable = lib.mkDefault true;
    source = profile.fontsPath;
    target = "fonts/user";
    onChange = "${pkgs.fontconfig}/bin/fc-cache -f -v";
  };

  # macOS doesn't use fontconfig to discover fonts from the Nix profile;
  # copy them into ~/Library/Fonts/Nix so the system font registry picks them up.
  home.activation.copyNixFonts = lib.mkIf pkgs.stdenv.isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      fontsDir="${config.home.homeDirectory}/Library/Fonts/Nix"
      mkdir -p "$fontsDir"
      rm -rf "$fontsDir"/*
      find "${config.home.profileDirectory}/share/fonts" \
        -type f \( -name '*.ttf' -o -name '*.otf' \) \
        -exec cp {} "$fontsDir/" \;
    ''
  );

  # User-provided icon themes
  xdg.dataFile.user-icons = lib.mkIf ((profile ? iconsPath) && profile.iconsPath != null) {
    enable = lib.mkDefault true;
    source = profile.iconsPath;
    target = "icons/user";
  };
}
