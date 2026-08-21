{ pkgs, lib, ... }:

# NOTE Some packages listed here are defined at the flake overlay
#   and thus may not appear when looked them up in nixpkgs.

{
  home.packages =
    with pkgs;
    [
      age
      attic-client
      bind
      curl
      diffutils
      fd
      gnutls
      htop
      jq
      less
      lsof
      procs
      ripgrep
      socat
      sops
      toolchains.nix
      tree
      trippy
      unzip
      websocat
      xh
      neovim
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      inotify-tools
      psmisc
      rng-tools
      smartmontools
    ];
}
