{
  lib,
  emacs31,
  doom-icon,
  fetchFromGitHub,
}:

# Emacs 31 carrying d12frosted/homebrew-emacs-plus's macOS patches and the Doom
# bundle icon. macOS only: every patch targets the NS/Cocoa port.
#
# No `.override`: nixpkgs's emacs31 already defaults withNS, withNativeCompilation,
# withSQLite3, withTreeSitter, withWebP and withMailutils the way we want on darwin.

let
  # Fetched as the whole repo, not per-file: patches can be symlinks into a
  # sibling emacs-NN dir, and raw.githubusercontent.com serves a symlink's
  # target path as text. A real checkout resolves them.
  emacsPlusSrc = fetchFromGitHub {
    owner = "d12frosted";
    repo = "homebrew-emacs-plus";
    rev = "cask-30-292";
    hash = "sha256-DH4iCOdxfkKYJLfdTOwhg6bCA712zdAe764W8NnQAGQ=";
  };

  patch = name: "${emacsPlusSrc}/patches/emacs-31/${name}";
in

emacs31.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    # Adds the setting for a rounded, undecorated window (still needs
    # default-frame-alist set to take effect).
    (patch "round-undecorated-frame.patch")

    # Make Emacs aware of the OS light/dark mode.
    # https://github.com/d12frosted/homebrew-emacs-plus#system-appearance-change
    (patch "system-appearance.patch")

    (patch "fix-ns-x-colors.patch")

    # That is the whole of patches/emacs-31/, and the whole of what upstream's
    # emacs-plus@31 formula applies. fix-window-role, fix-macos-tahoe-scrolling
    # and treesit-compatibility exist only for emacs-30 and earlier.
  ];

  # Replace the stock bundle icon. emacs-client copies Emacs.icns from here, so
  # this single swap covers both .apps.
  postInstall = (old.postInstall or "") + ''
    cp -f ${doom-icon}/share/doom.icns $out/Applications/Emacs.app/Contents/Resources/Emacs.icns
  '';

  meta = old.meta // {
    platforms = lib.platforms.darwin;
  };
})
