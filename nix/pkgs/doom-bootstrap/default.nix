{
  writeShellApplication,
  git,
  coreutils,
}:

# Doom's lifecycle (clone, `doom install`, `doom sync`) is a git checkout in
# $XDG_CONFIG_HOME/emacs, not something Nix can own - so it ships as a script
# both consumers call instead of a justfile recipe each keeps its own copy of.
#
# emacs, emacsclient, systemctl and launchctl deliberately stay out of
# runtimeInputs: they come from the user's profile and the OS, and pinning a
# second Emacs here would build Doom against a different binary than the daemon.

let
  # Only the Emacs module: this script has no use for the worktree and tmux half.
  emacsLib = ./../../modules/home-manager/programs/zsh/lib/emacs.sh;
in

writeShellApplication {
  name = "doom-bootstrap";

  runtimeInputs = [
    git
    coreutils
  ];

  text = builtins.replaceStrings [ "@emacsLib@" ] [ "${emacsLib}" ] (
    builtins.readFile ./doom-bootstrap.sh
  );
}
