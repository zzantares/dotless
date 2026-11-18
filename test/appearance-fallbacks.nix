# Proves every hook-written palette still lands when switching is off, the
# Darwin case: `dotless.appearance.enable = false`. Without a fallback the
# program finds no file and reverts to its stock theme, which is how the
# tmux status bar turned green on macOS.
{
  inputs,
  self,
  pkgs,
}:

let
  inherit (pkgs) lib;

  ciInputs = inputs // {
    dotless = self;
  };
  profile = import ./profile.nix;

  home =
    enable:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      extraSpecialArgs = {
        inputs = ciInputs;
        inherit profile;
      };

      modules = [
        self.homeModules.workstation
        (
          { lib, ... }:
          {
            home.username = "ci";
            home.homeDirectory = "/home/ci";
            home.stateVersion = "24.05";

            dotless.appearance.enable = lib.mkForce enable;

            sops.validateSopsFiles = false;
            sops.defaultSopsFile = lib.mkForce (builtins.toFile "ci-dummy-secrets.yaml" "{}\n");
          }
        )
      ];
    };

  off = (home false).config;
  on = (home true).config;

  # Every path a hook writes, so a hook added without a fallback is caught.
  hooked = lib.attrNames on.dotless.appearance.hooks;
  covered = lib.attrNames off.dotless.appearance.fallbacks;

  # These repaint a live process or rewrite a file that ships themed already,
  # so they need no fallback. Anything else must declare one.
  stateless = [
    "claude-code"
    "emacs"
    "gh-dash"
    "herdr"
    "nvim"
    "opencode"
  ];

  missing = lib.subtractLists (covered ++ stateless) hooked;
  stale = lib.subtractLists hooked covered;

  script = off.home.activation.appearanceFallback.data;
  targets = lib.mapAttrsToList (_: f: f.target) off.dotless.appearance.fallbacks;
in
assert lib.assertMsg (missing == [ ]) "appearance hooks with no fallback: ${toString missing}";
assert lib.assertMsg (stale == [ ]) "appearance fallbacks with no hook: ${toString stale}";

# The enabled side must not install them: the switch owns those paths there.
assert !(on.home.activation ? appearanceFallback);

pkgs.runCommand "appearance-fallbacks-check" { inherit script; } ''
  for target in ${lib.escapeShellArgs targets}; do
    if ! grep -qF "$target" <<<"$script"; then
      echo "appearance-fallbacks: nothing installs $target" >&2
      exit 1
    fi
  done

  # The source has to be a store path, not the linked copy: the fallback runs
  # whether or not linkGeneration has put that file in place.
  if grep -qE 'install -Dm644 /home/' <<<"$script"; then
    echo "appearance-fallbacks: a fallback installs from \$HOME, not the store" >&2
    exit 1
  fi

  touch $out
''
