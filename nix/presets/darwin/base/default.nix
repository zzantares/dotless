{
  profile,
  pkgs,
  lib,
  ...
}:

# Minimal shared configuration for nix-darwin systems.
# Sets the user's home directory so that home-manager (used as a nix-darwin
# module) can correctly derive home.homeDirectory without requiring
# users.users.${user}.home to be set manually in the system config.

{
  # The dotless overlay comes from the shared modules/nixpkgs module (deduplicated
  # so it applies once even when a config also imports it via modules/nix).
  imports = [ ./../../../modules/nixpkgs ];

  nixpkgs.config.allowUnfree = true;

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
    # nix-darwin's openssh module does not expose a structured settings attrset;
    # sshd_config directives go into extraConfig instead.
    extraConfig = ''
      PermitRootLogin no
      PasswordAuthentication no
      UseDns no
    '';
  };
}
