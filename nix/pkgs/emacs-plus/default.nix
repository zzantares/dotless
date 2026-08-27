{
  lib,
  emacs30,
  fetchFromGitHub,
  fetchurl,
}:

# Emacs 30 carrying d12frosted/homebrew-emacs-plus's macOS patches and the Doom
# bundle icon. macOS only: every patch targets the NS/Cocoa port.
#
# No `.override`: nixpkgs's emacs30 already defaults withNS, withNativeCompilation,
# withSQLite3, withTreeSitter, withWebP and withMailutils the way we want on darwin.

let
  # Fetched as the whole repo, not per-file: some patches under patches/emacs-30/
  # are symlinks into patches/emacs-28/, and raw.githubusercontent.com serves a
  # symlink's target path as text. A real checkout resolves them.
  emacsPlusSrc = fetchFromGitHub {
    owner = "d12frosted";
    repo = "homebrew-emacs-plus";
    rev = "cask-30-215";
    hash = "sha256-00X4Bqf4a+8TfDRFaSana2xdYPteWid5vubD9Z2eWKI=";
  };

  patch = name: "${emacsPlusSrc}/patches/emacs-30/${name}";

  # The official Doom Emacs icon (Dock / Finder / cmd-Tab), fetched as a prebuilt
  # multi-resolution icns. Swap `cute-doom` -> `abject-doom` for the alternate.
  # https://github.com/jaidetree/doom-icon
  icon = fetchurl {
    url = "https://raw.githubusercontent.com/jaidetree/doom-icon/0.0.3/cute-doom/doom.icns";
    sha256 = "0r1ikkpjrpga3k3yiyh2y292c70y1xhl8b2b9j5b6rkv718dakyh";
  };
in

emacs30.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    # Fix the OS window role so tiling WMs (yabai, AeroSpace) pick Emacs up.
    (patch "fix-window-role.patch")

    # Adds the setting for a rounded, undecorated window (still needs
    # default-frame-alist set to take effect).
    (patch "round-undecorated-frame.patch")

    # Make Emacs aware of the OS light/dark mode.
    # https://github.com/d12frosted/homebrew-emacs-plus#system-appearance-change
    (patch "system-appearance.patch")

    (patch "fix-ns-x-colors.patch")
    (patch "fix-macos-tahoe-scrolling.patch")

    # treesit-compatibility.patch is deliberately omitted: nixpkgs's emacs30
    # carries its own tree-sitter 0.26 patches, and this one rejects against
    # the already-patched src/treesit.c.
  ];

  # Replace the stock bundle icon. emacs-client copies Emacs.icns from here, so
  # this single swap covers both .apps.
  postInstall = (old.postInstall or "") + ''
    cp -f ${icon} $out/Applications/Emacs.app/Contents/Resources/Emacs.icns
  '';

  meta = old.meta // {
    platforms = lib.platforms.darwin;
  };
})
