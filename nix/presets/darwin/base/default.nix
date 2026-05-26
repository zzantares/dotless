{
  profile,
  inputs,
  pkgs,
  lib,
  ...
}:

# Minimal shared configuration for nix-darwin systems.
# Sets the user's home directory so that home-manager (used as a nix-darwin
# module) can correctly derive home.homeDirectory without requiring
# users.users.${user}.home to be set manually in the system config.

{
  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [ inputs.dotless.overlays.default ];

  time.timeZone = lib.mkIf (profile ? timeZone) profile.timeZone;

  users.users."${profile.login}" = {
    # Required for home-manager to derive home.homeDirectory correctly.
    home = lib.mkDefault "/Users/${profile.login}";
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    dnsutils
    ncdu
    netcat
    nmap
    whois
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      UseDns = false;
    };
  };

  # Expose /nix/store over SSH to authorized identities.
  nix.sshServe = {
    enable = true;
    trusted = false;
    protocol = "ssh-ng";
    keys = profile.sshKeys;
  };
}
