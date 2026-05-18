{
  pkgs,
  ...
}:

let
  system-fonts = with pkgs; [
    overpass
    noto-fonts
    ubuntu-sans
    inconsolata
    cascadia-code
    jetbrains-mono
  ];

  nerdfonts = with pkgs.nerd-fonts; [
    _0xproto
    caskaydia-cove
    caskaydia-mono
    code-new-roman
    droid-sans-mono
    fantasque-sans-mono
    fira-code
    hack
    hasklug
    inconsolata
    jetbrains-mono
    meslo-lg
    overpass
    roboto-mono
    sauce-code-pro
    ubuntu-mono
  ];

in
pkgs.buildEnv {
  name = "fonts";
  paths = system-fonts ++ nerdfonts;
}
