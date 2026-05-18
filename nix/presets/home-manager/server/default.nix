{ ... }:

# This is the place to put configuration that makes sense for a
# server only accessible through the network, therefore settings that touch
# on desktop sessions, resolution, icons, fonts, GUI applications, do not
# make sense to add here.

{
  imports = [
    ./../base
    ./../../../modules/home-manager/programs/zsh-bare
    ./packages.nix
  ];
}
