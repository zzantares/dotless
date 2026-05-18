{
  config,
  pkgs,
  osConfig ? null,
  ...
}:

# NOTE Some packages listed here are defined at the flake overlay
#   and thus may not appear when looked them up in nixpkgs.

{
  home.packages = with pkgs; [
    (config.lib.nixGL.wrap nyxt) # TODO use "programs.nyxt" instead
    element-desktop
    gimp
    languagetool
    ladybird
    zed-editor
    slack
    spotify
    xournalpp
    zeal
  ];
}
