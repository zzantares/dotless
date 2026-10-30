{
  lib,
  symlinkJoin,
  writeShellApplication,
  coreutils,
  curl,
  diffnav,
  findutils,
  gawk,
  gh,
  git,
  gnugrep,
  jq,
}:

# The worktree front ends for the shell library this repo ships under
# ~/.local/lib/sh, which until now had no assembled tool to go with it:
# `git wt` starts and finishes a branch of your own, `git pr` checks out
# someone else's, and `pr-diff` / `pr-review` are what the gh-dash keys in the
# devstation preset call to read and review one.
#
# `pr-review` needs octo.nvim configured in your own neovim; dotless does not
# wire that up, since it owns no neovim config (unlike Emacs, where it ships
# `nitpick` outright). Without octo, `R` opens nvim and `Octo` is undefined.
#
# zoxide and claude stay out of runtimeInputs: git-pr only uses them when they
# are already on the caller's PATH, and pinning either would pull a second copy
# into every consumer's closure.

let
  shLib = ./../../modules/home-manager/programs/zsh/lib;

  mk =
    name: runtimeInputs:
    writeShellApplication {
      inherit name runtimeInputs;

      # Exported above the script body, so the `source` line reads as a normal
      # variable rather than a build-time placeholder (cf. boom).
      runtimeEnv.DOTLESS_SH_LIB = "${shLib}";

      text = builtins.readFile (./. + "/${name}.sh");
    };

  git-main-branch = mk "git-main-branch" [ git ];

  # `timeout` bounds git-wt's fetch and comes from coreutils; it falls back to
  # gtimeout and then to no bound, so a darwin box without either still works.
  git-wt = mk "git-wt" [
    coreutils
    git
    git-main-branch
    gnugrep
  ];

  # `git pr` resolves through PATH, so the sibling tools carry git-pr itself
  # rather than relying on both being installed in the same profile.
  git-pr = mk "git-pr" [
    coreutils
    curl
    findutils
    gawk
    gh
    git
    git-main-branch
    gnugrep
    jq
  ];
in
symlinkJoin {
  name = "pr-tools";

  paths = [
    git-main-branch
    git-pr
    git-wt
    (mk "pr-diff" [
      coreutils
      diffnav
      git
      git-pr
    ])
    (mk "pr-review" [
      coreutils
      git
      git-pr
    ])
  ];

  meta = {
    description = "Start, check out, read and review branches and pull requests in sibling worktrees";
    platforms = lib.platforms.unix;
  };
}
