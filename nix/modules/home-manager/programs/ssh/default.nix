{
  profile,
  config,
  pkgs,
  lib,
  ...
}:

{
  services.ssh-agent = {
    enable = lib.mkDefault false; # So that we use GNOME integration which has better UX
    package = config.programs.ssh.package;
    defaultMaximumIdentityLifetime = 14400;
  };

  # This only handles the SSH client configuration not the installation of the client
  programs.ssh = {
    enable = lib.mkDefault true;
    package = pkgs.openssh; # NOTE not setting this means to use the system's SSH
    enableDefaultConfig = false;

    # Options are taken as they are encountered from top to bottom
    matchBlocks = {
      "codeberg.org" = {
        # We do this to speed up connections to codeberg (there's no IPv6 support)
        addressFamily = "inet";
      };

      "*" = {
        forwardAgent = false;
        addKeysToAgent = "yes";
        compression = true; # Speeds up X forwarding

        # Control connection heartbeat (disconnect after 5 minutes when no answer from server)
        serverAliveInterval = 30;
        serverAliveCountMax = 5;

        # NOTE we want `~` here so that paths are dynamically resolved
        hashKnownHosts = true;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        controlPersist = "no";

        identityFile = "~/.ssh/id_ed25519";
      };
    } // (profile.sshMatchBlocks or {});
  };

  # Declare authorized SSH keys
  home.file.ssh_authorized_keys = {
    enable = lib.mkDefault true;

    # TODO pull base keys from profile
    text = lib.strings.concatLines (
      [ "# File managed by HomeManager - any changes will be overwritten" ] ++ profile.sshKeys
    );

    # This file can not be a regular /nix/store symlink unless disabling
    # strict checking which is undesirable. Therefore we detect when the
    # file content changes and `cat` the contents into place.
    onChange = ''
      cat ${config.home.file.ssh_authorized_keys.target} > ${config.home.homeDirectory}/.ssh/authorized_keys && \
        chmod 600 ${config.home.homeDirectory}/.ssh/authorized_keys
    '';
  };
}
