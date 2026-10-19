# Proves the Zed option tree composes: a consumer overrides one nested
# setting, adds a key, and appends a keymap block, without restating the rest.
{
  inputs,
  self,
  pkgs,
}:

let
  profile = import ./profile.nix;

  consumer = {
    # Nested leaf override; sibling leaves (theme.light, theme.mode) must survive.
    dotless.editors.zed.settings.theme.dark = "Ayu Dark";

    # New key, merged alongside dotless's own.
    dotless.editors.zed.settings.soft_wrap = "editor_width";

    # Zed reads later blocks as the winner, so mkAfter is the override.
    dotless.editors.zed.keymap = pkgs.lib.mkAfter [
      {
        context = "Editor && !menu";
        bindings."ctrl-s" = "workspace::SaveAll";
      }
    ];
  };

  hm = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit profile; };
    modules = [
      self.homeModules.zed
      consumer
      {
        home.username = "ci";
        home.homeDirectory = "/home/ci";
        home.stateVersion = "24.05";
      }
    ];
  };

  settings = hm.config.xdg.configFile."zed/settings.json".source;
  keymap = hm.config.xdg.configFile."zed/keymap.json".source;
in
pkgs.runCommand "zed-compose-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
  check() {
    local got
    got="$(jq -r "$2" "$1")"
    if [[ "$got" != "$3" ]]; then
      echo "zed-compose: $2 = '$got', expected '$3'" >&2
      exit 1
    fi
  }

  # Overridden leaf, untouched siblings, added key.
  check ${settings} '.theme.dark' 'Ayu Dark'
  check ${settings} '.theme.light' 'One Light'
  check ${settings} '.theme.mode' 'system'
  check ${settings} '.soft_wrap' 'editor_width'
  check ${settings} '.vim_mode' 'true'
  check ${settings} '.languages.C.format_on_save' 'on'

  # dotless's blocks kept, consumer's block appended last and winning.
  check ${keymap} 'length' '13'
  check ${keymap} '.[0].context' 'Workspace'
  check ${keymap} '.[-1].context' 'Editor && !menu'
  check ${keymap} '.[-1].bindings["ctrl-s"]' 'workspace::SaveAll'

  touch $out
''
