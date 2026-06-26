{
  profile,
  pkgs,
  ...
}:

# Configuration for systems installed on real hardware — bootable machines
# with login access (not containers or VMs).

{
  imports = [ ./../base ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  users.groups = {
    # Only members of this group are allowed remote SSH login.
    remote = { };
  };

  users.users."${profile.login}" = {
    isNormalUser = true;
    home = "/home/${profile.login}";
    description = profile.name;
    extraGroups = [
      "audio"
      "networkmanager"
      "remote"
      "syncthing"
      "video"
      "wheel"
    ];
    shell = pkgs.zsh;
    packages = [ ]; # User-level packages are managed by home-manager.
    openssh.authorizedKeys.keys = profile.sshKeys;
  };

  # Restrict SSH access to members of the remote group (defined above).
  services.openssh.settings.AllowGroups = [ "remote" ];

  environment.systemPackages = with pkgs; [
    parted
    ntfs3g
    gparted
    lm_sensors
    pciutils
    usbutils
    toolchains.network
  ];

  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowPing = false;
    allowedTCPPorts = [ 22 ];
    trustedInterfaces = [ "tailscale0" ];
  };
}
