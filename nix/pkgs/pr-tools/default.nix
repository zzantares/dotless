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

# The PR review tools, as the gh-dash keybindings in the devstation preset call
# them: `git pr` checks a PR out as a sibling worktree, `pr-diff` reads it in
# diffnav and `pr-review` opens it in nvim.
#
# `pr-review` needs octo.nvim configured in your own neovim; dotless does not
# wire that up, since it owns no neovim config (unlike Emacs, where it ships
# `revu` outright). Without octo, `R` opens nvim and `Octo` is undefined.
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
    description = "Check out, read and review a pull request from a sibling worktree";
    platforms = lib.platforms.unix;
  };
}
