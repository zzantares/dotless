{
  lib,
  trivialBuild,
  gh,
}:

# Byte-compiled without magit/forge/diff-hl in scope: those are provided by the
# user's Emacs config (Doom installs them with straight), and pulling a second
# copy into the wrapper would shadow it. `declare-function' keeps the compiler
# quiet about them.
trivialBuild {
  pname = "revu";
  version = "0.1.0";

  src = lib.sources.sourceFilesBySuffices ./. [ ".el" ];

  # `gh' must be the GitHub CLI from the top-level package set: the emacs scope
  # this is called from also has a `gh' (an elisp API library), and callPackage
  # picks that one unless the caller passes it explicitly. Fail loudly if so.
  postPatch = ''
    test -x ${lib.getExe' gh "gh"}
    substituteInPlace revu.el \
      --replace-fail '(defcustom revu-gh-executable "gh"' \
                     '(defcustom revu-gh-executable "${lib.getExe' gh "gh"}"'
  '';

  # trivialBuild byte-compiles and installs the top-level *.el only, so the
  # suite under test/ is available to run but never ships.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    emacs --batch -L . -l ert -l revu -l test/revu-test.el \
      -f ert-run-tests-batch-and-exit
    runHook postCheck
  '';

  # A byte-compiler warning fails the build; `declare-function' above is what
  # keeps the absent magit/forge/diff-hl from tripping it.
  turnCompilationWarningToError = true;

  meta = {
    description = "Batched pull request reviews from Emacs, anchored on the files on disk";
    homepage = "https://git.gutimore.net/gutimore/dotless";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
