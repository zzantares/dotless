# Proves the signal source is replaceable and that the Linux provider still
# reads the portal. The smoke configs only check that the module evaluates, so
# without this a refactor could drop a rung of the chain in silence.
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
    extra:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      extraSpecialArgs = {
        inputs = ciInputs;
        inherit profile;
      };

      modules = [
        self.homeModules.workstation
        extra
        (
          { lib, ... }:
          {
            home.username = "ci";
            home.homeDirectory = "/home/ci";
            home.stateVersion = "24.05";

            sops.validateSopsFiles = false;
            sops.defaultSopsFile = lib.mkForce (builtins.toFile "ci-dummy-secrets.yaml" "{}\n");
          }
        )
      ];
    };

  # The default on this platform.
  linux = (home { }).config;

  # A consumer's own provider, to show the set is genuinely open.
  custom =
    (home {
      dotless.appearance.provider = "fromtest";
      dotless.appearance.providers.fromtest.detect = "echo light # provider-from-test";
    }).config;

  switchOf =
    cfg:
    lib.getExe (lib.head (lib.filter (p: p.pname or p.name == "appearance-switch") cfg.home.packages));

  unit = linux.systemd.user.services.appearance-switch;
in
# A provider with no `watch` must not leave a unit behind that runs nothing.
assert !(custom.systemd.user.services ? appearance-switch);

pkgs.runCommand "appearance-provider-check"
  {
    linuxSwitch = switchOf linux;
    customSwitch = switchOf custom;
    watcher = unit.Service.ExecStart;
  }
  ''
    need() {
      if ! grep -qF "$2" "$1"; then
        echo "appearance-provider: $3" >&2
        exit 1
      fi
    }

    # Both rungs of the chain, so neither can be dropped quietly.
    need "$linuxSwitch" 'org.freedesktop.portal.Settings.$1' \
      'the linux detect no longer calls the portal'
    need "$linuxSwitch" 'portal ReadOne || portal Read' \
      'the linux detect no longer falls back to the deprecated Read'
    need "$linuxSwitch" 'gsettings get org.gnome.desktop.interface color-scheme' \
      'the linux detect no longer falls back to gsettings'

    # The watcher filters on the bus, not with a text match over every signal.
    need "$watcher" "arg0='org.freedesktop.appearance'" \
      'the watcher no longer filters the signal with a match rule'
    need "$watcher" 'gsettings monitor' \
      'the watcher no longer falls back to gsettings monitor'

    # A consumer's provider reaches the script, which is the whole point of the
    # set being open.
    need "$customSwitch" 'provider-from-test' \
      'a provider defined outside dotless did not reach appearance-switch'
    if grep -qF 'org.freedesktop.portal' "$customSwitch"; then
      echo "appearance-provider: the chosen provider did not replace the default" >&2
      exit 1
    fi

    touch $out
  ''
