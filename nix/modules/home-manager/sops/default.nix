{
  config,
  inputs,
  profile,
  ...
}:

{
  imports = [ inputs.sops-nix.homeModules.sops ];

  sops = {
    defaultSopsFile = "${inputs.self}/secrets/${profile.login}/secrets.yaml";

    # TODO Configure sops to use age keys instead (put together an easy key-rotation script)
    # age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key"

    gnupg.home = "${config.home.homeDirectory}/.gnupg";
  };
}
