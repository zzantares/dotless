{
  config,
  pkgs,
  lib,
  profile,
  ...
}:

let
  identityFile = "${config.home.homeDirectory}/${profile.identityFile}";

  ssh-agent-signer = import ../ssh-agent-signer.nix { inherit pkgs lib identityFile; };

  # Written by the git module; jj only reads it to verify signatures.
  allowedSigners = "${config.xdg.configHome}/git/allowed-signers";

  delta = lib.getExe config.programs.delta.finalPackage;
in
{
  programs.jujutsu = {
    enable = lib.mkDefault true;

    settings = {
      user.name = profile.name;
      user.email = profile.email;

      # Same SSH key, agent wrapper and allowed-signers file as git, so
      # `git log --show-signature` and `jj log` agree on colocated repos.
      signing = {
        backend = "ssh";
        behavior = lib.mkDefault "own";
        key = identityFile;
        backends.ssh = {
          program = "${ssh-agent-signer}/bin/ssh-agent-signer";
          allowed-signers = allowedSigners;
        };
      };

      git.sign-on-push = true;

      ui = {
        paginate = "auto";
        pager = "less -XFRS";
        editor = "nvim";
        # Bare `jj` errors out otherwise.
        default-command = "log";
        show-cryptographic-signatures = true;
      }
      // lib.optionalAttrs config.programs.jujutsu.ediff { merge-editor = "ediff"; };

      # Nearest bookmark at or below a revision — what `tug` advances.
      revset-aliases."closest_bookmarks(to)" = "heads(::to & bookmarks())";

      aliases = {
        # Advance the closest bookmark onto the parent of the working copy,
        # the jj equivalent of a git branch following your commits.
        tug = [
          "bookmark"
          "move"
          "--from"
          "closest_bookmarks(@-)"
          "--to"
          "@-"
        ];

        patch = [
          "--no-pager"
          "diff"
          "--git"
          "--color=never"
        ];
      }
      // lib.optionalAttrs config.programs.delta.enable {
        # Mirrors `git df`: the default diff stays color-words under less,
        # `jj df` opts in to git-style hunks through delta.
        df = [
          "--config"
          "ui.diff-formatter=:git"
          "--config"
          "ui.pager=${delta}"
          "diff"
        ];
      };
    };
  };
}
