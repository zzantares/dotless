{ runCommand }:

# Bundles the wallpapers shipped by dotless into a derivation so that modules
# can reference them via `pkgs.wallpapers` without depending on `inputs.self`.
runCommand "dotless-wallpapers" { } ''
  cp -r ${../../../resources/wallpapers} $out
''
