# Placeholder profile so the preset modules evaluate in CI. Fields guarded by
# `profile ? x` are omitted; `wallpaper` is required (gnome interpolates it).
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
