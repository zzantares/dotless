{
  profile,
  config,
  lib,
  ...
}:

{
  services.syncthing = {
    enable = lib.mkDefault true;
    user = profile.login;
    systemService = lib.mkDefault true;
    openDefaultPorts = lib.mkDefault true;
    dataDir = "${config.users.users."${profile.login}".home}/Sync";
    configDir = "${config.users.users."${profile.login}".home}/.config/syncthing";
  };
}
