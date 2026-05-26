{
  profile,
  inputs,
  pkgs,
  lib,
  ...
}:

# Minimal shared configuration suitable for any managed NixOS system.
# Does not assume a desktop, GPU, or any specific hardware.
# Import this as the foundation and extend with bare-metal, server, or desktop.

{
  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [ inputs.dotless.overlays.default ];

  time.timeZone = lib.mkIf (profile ? timeZone) profile.timeZone;

  # Expose /nix/store over SSH to authorized identities, enabling use of
  # "--substituters ssh://user@host" on other machines to copy cached paths.
  nix.sshServe = {
    enable = true;
    trusted = false;
    protocol = "ssh-ng";
    keys = profile.sshKeys;
  };

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  environment.systemPackages = with pkgs; [
    dnsutils
    ncdu
    netcat
    nmap
    whois
  ];

  services.printing.enable = false;
  services.printing.browsed.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      UseDns = false;
    };
  };
}
