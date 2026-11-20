# Evaluates the darwin side on a linux runner. Nothing else does: the smoke
# configs are x86_64-linux, so before this a change could break every mac and
# CI would stay green.
#
# Every assertion is an eval-time one over option values, and the derivation at
# the end takes no inputs. Passing a darwin store path into a builder would
# make it a build dependency, and a linux machine cannot build one.
{
  inputs,
  self,
  pkgs,
}:

let
  inherit (pkgs) lib;

  profile = import ./profile.nix;

  configFor =
    system:
    let
      hostPkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ self.overlays.default ];
      };
    in
    (inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = hostPkgs;

      extraSpecialArgs = {
        inputs = inputs // {
          dotless = self;
        };
        inherit profile;
      };

      modules = [
        self.homeModules.devstation
        (
          { lib, ... }:
          {
            home.username = "ci";
            home.homeDirectory = if hostPkgs.stdenv.hostPlatform.isDarwin then "/Users/ci" else "/home/ci";
            home.stateVersion = "24.05";

            sops.validateSopsFiles = false;
            sops.defaultSopsFile = lib.mkForce (builtins.toFile "ci-dummy-secrets.yaml" "{}\n");
          }
        )
      ];
    }).config;

  darwin = configFor "aarch64-darwin";
  linux = configFor "x86_64-linux";

  agent = darwin.launchd.agents.appearance-switch.config;
  provider = darwin.dotless.appearance.providers.darwin;

  names = ps: map (p: p.pname or p.name or "") ps;
  pathNames = lib.concatStringsSep " " (names provider.path);

  # The agent's command, as text. Discarding the context keeps this a plain
  # string rather than a reference to something a linux builder must realise.
  watchCommand = builtins.unsafeDiscardStringContext (
    lib.concatStringsSep " " agent.ProgramArguments
  );
in
# Switching has to be on, or nothing below proves anything.
assert lib.assertMsg darwin.dotless.appearance.enable "appearance switching is off on darwin";

# One supervisor each, and never the other platform's.
assert lib.assertMsg (
  !(darwin.systemd.user.services ? appearance-switch)
) "darwin carries a systemd unit";
assert lib.assertMsg (
  !((linux.launchd.agents or { }) ? appearance-switch)
) "linux carries a launchd agent";

# launchd has no graphical-session.target to pull the agent in, so these two
# are what make it run at all.
assert lib.assertMsg (agent.RunAtLoad == true) "the launchd agent does not run at load";
assert lib.assertMsg (agent.KeepAlive == true) "the launchd agent is not kept alive";
assert lib.assertMsg (lib.hasInfix "appearance-watch" watchCommand)
  "the launchd agent does not run appearance-watch";

# `defaults` by absolute path: writeShellApplication only prepends to PATH, and
# nothing guarantees /usr/bin is on the inherited one.
assert lib.assertMsg (lib.hasInfix "/usr/bin/defaults read -g AppleInterfaceStyle" provider.detect)
  "the darwin detect no longer reads AppleInterfaceStyle by absolute path";

# Light leaves the key unset, so the absent case must answer light, and a
# missing binary must answer dark like linux does with nothing to follow.
assert lib.assertMsg (
  lib.hasInfix "echo light" provider.detect && lib.hasInfix "-x /usr/bin/defaults" provider.detect
) "the darwin detect no longer handles the absent key and the absent binary";

assert lib.assertMsg (lib.hasInfix "dark-mode-notify" provider.watch)
  "the darwin watcher no longer runs dark-mode-notify";

# Each platform's tooling stays out of the other's provider, which is the
# reason the commands live in one.
assert lib.assertMsg (
  pathNames == "dark-mode-notify"
) "darwin's provider path should be dark-mode-notify alone, got '${pathNames}'";

assert lib.assertMsg (
  !(lib.hasInfix "dark-mode-notify" linux.dotless.appearance.providers.linux.detect)
) "the linux provider reaches for dark-mode-notify";

pkgs.runCommand "appearance-darwin-check" { } "touch $out"
