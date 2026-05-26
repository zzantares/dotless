{
  profile,
  config,
  ...
}:

{
  services.syncthing = {
    enable = true;
    user = profile.login;
    systemService = true;
    openDefaultPorts = true;
    dataDir = "${config.users.users."${profile.login}".home}/Sync";
    configDir = "${config.users.users."${profile.login}".home}/.config/syncthing";
  };
}
