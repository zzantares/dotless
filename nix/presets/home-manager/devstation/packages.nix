{
  pkgs,
  lib,
  osConfig ? null,
  ...
}:

# NOTE Some packages listed here are defined at the flake overlay
#   and thus may not appear when looked them up in nixpkgs.

{
  home.packages =
    with pkgs;
    [
      aspell-with-dicts
      diffnav
      entr
      fonts
      forgejo-cli
      fzf
      git
      git-extras
      git-lfs
      gh-dash
      just
      man-pages-posix
      latex-with-packages # needed for org-export commands in emacs
      libfaketime
      pass # TODO check out bitwarden-cli?
      pre-commit
      tree-sitter
      tea-dash
      tealdeer
      toolchains.android
      toolchains.lisp
      toolchains.lua
      toolchains.markdown
      toolchains.ops
      toolchains.postgresql
      toolchains.python
      toolchains.rust
      toolchains.shell
      toolchains.typescript
      toolchains.web
      yq
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      linux-manual
      man-pages
      wikiman # TODO see how to install it with additional sources (tldr, arch)
      wol
      xclip
      xsel
    ]
    # HomeManager doesn't uses `nix.enable` so we have to add it manually (from the overlay)
    # but on NixOS systems we do have Nix at the system level so we don't want to add it
    ++ (if osConfig != null then [ ] else [ nix ]);
}
