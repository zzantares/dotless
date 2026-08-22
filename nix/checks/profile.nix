# Placeholder `profile` for the CI smoke configs.
#
# Real consumers pass their own `profile` via specialArgs; this is a
# type-correct dummy that lets the preset modules evaluate. Fields the modules
# guard with `profile ? x` (e.g. fontsPath/iconsPath/wallpapersPath) are omitted
# on purpose; `wallpaper` is included because the gnome module interpolates it
# unconditionally.
{
  name = "CI User";
  user = "ci";
  login = "ci";
  email = "ci@example.com";
  emailAddresses = [ "ci@example.com" ];
  emailAfewRules = "";
  timeZone = "UTC";
  flakeRoot = "dotless";
  identityFile = ".ssh/id_ed25519.pub";
  gpgKey = "";
  smtpTlsFingerprint = "";
  alacrittyColors = "kanagawa";
  gnomeAccentColor = "blue";
  ohMyZshTheme = "robbyrussell";
  shellAliases = { };
  sshKeys = [ ];
  sshMatchBlocks = { };
  wallpaper = "/var/empty/wallpaper.png";
}
