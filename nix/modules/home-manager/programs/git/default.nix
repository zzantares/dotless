{
  config,
  pkgs,
  lib,
  profile,
  ...
}:

# FIXME we need to separate this module into options oriented
#   for gitops environments and others oriented for developer environments

let
  identityFile = "${config.home.homeDirectory}/${profile.identityFile}";

  # We need a custom script to add the key to the agent when signing a commit
  # because AddKeysToAgent in ssh config is not honored when signing (it's not a
  # connection attempt)
  ssh-agent-signer = pkgs.writeShellScriptBin "ssh-agent-signer" ''
    #!/usr/bin/env bash
    # Check if the signing key is already in the agent.
    # Uses ssh-add -l rather than -T: gpg-agent does not implement -T, causing
    # it to fall through to `ssh-add <pubkey>` which then fails with
    # "error in libcrypto: unsupported" (you cannot add a public key to an agent).
    fingerprint=$(ssh-keygen -lf "${identityFile}" 2>/dev/null | awk '{print $2}')
    ssh-add -l 2>/dev/null | grep -qF "$fingerprint" \
      || ssh-add "${lib.removeSuffix ".pub" identityFile}" 2>/dev/null \
      || true
    exec ssh-keygen "$@"
  '';
in
{
  home.packages = with pkgs; [ git-crypt ];

  home.file.allowed-signers = {
    enable = config.programs.git.signing.signByDefault;
    target = "${config.xdg.configHome}/git/allowed-signers";

    text =
      let
        signers = lib.cartesianProduct {
          address = profile.emailAddresses;
          identity = profile.sshKeys;
        };

        asAllowedSigner = signer: "${signer.address} ${signer.identity}";
      in
      lib.strings.concatLines (lib.map asAllowedSigner signers);
  };

  # provides better diffs
  programs.delta = {
    enable = lib.mkDefault true;
    # Default to manual integration so diff uses less and `git df` opts in to
    # delta. Set enableGitIntegration = true to restore full auto-integration.
    enableGitIntegration = lib.mkDefault false;
    options = {
      dark = true;
      navigate = true; # use n and N to move between diff sections
      line-numbers = true;
      side-by-side = true;
    };
  };

  programs.lazygit = {
    enable = true;
    package = pkgs.lazygit;
    enableZshIntegration = true;
    shellWrapperName = "lg";

    # See: https://github.com/jesseduffield/lazygit/blob/master/docs/Config.md
    # settings = { };
  };

  programs.git = {
    enable = lib.mkDefault true;

    ignores = [
      "*.log"
      "*~"
      ".DS_Store"
      ".cpcache"
      ".envrc"
      ".idea"
      ".jj"
      ".vim/bundle/"
      ".vim/eclim/"
      "TAGS"
      "Thumbs.db"
      "nix/netrc"
      "nvim/.netrwhist"
      ".code-workspace"
      "codebase-explorer"
    ];

    lfs = {
      enable = lib.mkDefault true;
      package = pkgs.git-lfs;
      # Resolve binary files LFS pointers to the actual objects automatically
      skipSmudge = false;
    };

    signing = {
      format = "ssh";
      key = identityFile;
      signByDefault = lib.mkDefault true;
      signer = "${ssh-agent-signer}/bin/ssh-agent-signer";
    };

    settings = lib.mkMerge [
      (lib.mkIf (config.programs.delta.enable && !config.programs.delta.enableGitIntegration) {
        # When not using delta's full auto-integration, wire up blame/log/show
        # manually and expose `git df` to opt in to delta for diff on demand.
        pager = {
          blame = lib.getExe config.programs.delta.finalPackage;
          log = lib.getExe config.programs.delta.finalPackage;
          show = lib.getExe config.programs.delta.finalPackage;
        };
        interactive.diffFilter = "${lib.getExe config.programs.delta.finalPackage} --color-only";
        alias.df = "-c pager.diff=${lib.getExe config.programs.delta.finalPackage} diff";
      }){
      # NOTE git's user.signingKey setting is already set because of `programs.git.signing.key` above
      user = {
        name = profile.name;
        email = profile.email;
      };

      # NOTE `programs.git.signing` option doesn't create this which is required by `git verify-commit` cmd
      gpg.ssh.allowedSignersFile = "${config.home.homeDirectory}/${config.home.file.allowed-signers.target}";

      core.editor = "nvim";
      init.defaultBranch = "master";
      fetch.prune = true;
      github.user = profile.user;
      gitlab."gitlab.haskell.org/api/v4".user = profile.user;
      submodule.recurse = true;
      merge.conflictstyle = "zdiff3";

      # The HomeManager module doesn't expose a config option to setting this, so we put it here.
      lfs.locksverify = true;

      pull = {
        rebase = true;
        ff = "only";
      };

      rebase = {
        autoStash = true;
        updateRefs = true;
      };

      # Because we use Magit most of the time, and magits has a different notion
      # of what the "upstream" branch should be we configure the push branch to
      # be the one with the same name than the current branch in the remote.
      # I've seen some weird behavior when mixing Magit and git-spice and I
      # think it has to do with this mismatch on what the upstream branch is.
      # See https://blog.mplanchard.com/posts/set-your-upstream-to-the-true-upstream.html
      push.default.current = true;

      color = {
        ui = true;
        pager = true;
      };

      alias = {
        logs = "log --first-parent --color --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        graph = "log --graph --color --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        # pruner = "!git fetch origin --prune && git branch --merged master | rg -v '(^\*\\|^\+\\|master\\|main\\|prod\\|staging\\|dev\\|test)' | xargs -r git branch --delete";
        purge = "!git fetch origin --prune; git branch --merged master | rg -v '(^\*|^\+|master|main|prod|staging|dev|test)' | xargs -r echo git brrrr";
        patch = "!git --no-pager diff --no-color";
        wip = "commit --all --no-verify --no-gpg-sign --message '[skip ci] WIP'";
        co = "!fzf-git-checkout";
        br = "!fzf-git-branch";
      };

    }];
  };
}
