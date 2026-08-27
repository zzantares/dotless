{
  profile,
  config,
  pkgs,
  lib,
  ...
}:

{
  services.ssh-agent = {
    enable = lib.mkDefault false; # Prefer desktop-provided agents (GNOME keyring, gpg-agent) over the standalone ssh-agent
    package = config.programs.ssh.package;
    defaultMaximumIdentityLifetime = 14400;
  };

  # HM only exports SSH_AUTH_SOCK from shell inits plus a oneshot unit that races
  # every other user service. Losers (the Emacs daemon, so Magit's git) start
  # without an agent and re-prompt for the key passphrase. environment.d is set
  # before any unit starts; both agents listen on a fixed path.
  systemd.user.sessionVariables = lib.mkIf config.sshAuthSock.enable {
    SSH_AUTH_SOCK =
      if config.services.ssh-agent.enable then
        "\${XDG_RUNTIME_DIR}/${config.services.ssh-agent.socket}"
      else
        "\${XDG_RUNTIME_DIR}/gnupg/S.gpg-agent.ssh";
  };

  # This only handles the SSH client configuration not the installation of the client
  programs.ssh = {
    enable = lib.mkDefault true;
    package = pkgs.openssh; # NOTE not setting this means to use the system's SSH
    enableDefaultConfig = false;

    # Options are taken as they are encountered from top to bottom
    settings = {
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
        controlPath = "~/.ssh/master-%C";
        controlPersist = "no";

        identityFile = "~/.ssh/id_ed25519";
      };
    }
    // (profile.sshMatchBlocks or { });
  };

  # Declare authorized SSH keys
  home.file.ssh_authorized_keys = {
    enable = lib.mkDefault true;

    # TODO pull base keys from profile
    text = lib.strings.concatLines (
      [ "# File managed by HomeManager - any changes will be overwritten" ] ++ profile.sshKeys
    );
  };

  # This file can not be a regular /nix/store symlink unless disabling strict
  # checking which is undesirable. Use home.activation (runs on every switch,
  # not just on content changes) so the file is always present with correct
  # permissions — including on fresh systems and after accidental deletion.
  home.activation.writeAuthorizedKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -Dm600 \
      "${config.home.homeDirectory}/${config.home.file.ssh_authorized_keys.target}" \
      "${config.home.homeDirectory}/.ssh/authorized_keys"
  '';
}
