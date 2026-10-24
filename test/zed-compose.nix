# Proves the Zed split: the keymap is a Nix list a consumer appends to, and the
# settings base ships as JSONC Zed can parse (Zed merges that below the
# consumer's own settings.json, which dotless never writes).
{
  inputs,
  self,
  pkgs,
}:

let
  inherit (pkgs) lib;
  profile = import ./profile.nix;

  consumer = {
    # Zed reads later blocks as the winner, so mkAfter is the override.
    dotless.editors.zed.keymap = lib.mkAfter [
      {
        context = "Editor && !menu";
        bindings."ctrl-s" = "workspace::SaveAll";
      }
    ];
  };

  mkHome =
    extra:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit profile; };
      modules = [
        self.homeModules.zed
        consumer
        extra
        {
          home.username = "ci";
          home.homeDirectory = "/home/ci";
          home.stateVersion = "24.05";
        }
      ];
    };

  files = (mkHome { }).config.xdg.configFile;
  keymap = files."zed/keymap.json".source;
  globalSettings = files."zed/global_settings.json".source;

  # Opting in links the consumer's own settings.json; dotless never writes one.
  optedIn = (mkHome { dotless.editors.zed.userSettings = true; }).config.xdg.configFile;
  userSettings = optedIn."zed/settings.json".source;
in
assert !(builtins.hasAttr "zed/settings.json" files);
assert builtins.hasAttr "zed/settings.json" optedIn;
pkgs.runCommand "zed-compose-check"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.python3
    ];
  }
  ''
    check() {
      local got
      got="$(jq -r "$2" "$1")"
      if [[ "$got" != "$3" ]]; then
        echo "zed-compose: $2 = '$got', expected '$3'" >&2
        exit 1
      fi
    }

    # dotless's blocks kept, consumer's block appended last and winning.
    check ${keymap} '.[0].context' 'Workspace'
    check ${keymap} 'any(.[]; .bindings["space t t"] == "pane::RevealInProjectPanel")' 'true'
    check ${keymap} '.[-1].context' 'Editor && !menu'
    check ${keymap} '.[-1].bindings["ctrl-s"]' 'workspace::SaveAll'

    # dotless's own ctrl-s block survives, ahead of the consumer's.
    check ${keymap} '[.[] | select(.bindings["ctrl-s"])] | length' '2'
    check ${keymap} '[.[] | select(.bindings["ctrl-s"])] | .[0].bindings["ctrl-s"]' 'workspace::Save'

    python3 ${./zed-global-settings-check.py} ${globalSettings}

    # userSettings must reach the consumer's repo, not the store.
    target="$(readlink ${userSettings})"
    if [[ "$target" != "/home/ci/dotless/config/zed/settings.json" ]]; then
      echo "zed-compose: userSettings links to '$target'" >&2
      exit 1
    fi

    touch $out
  ''
