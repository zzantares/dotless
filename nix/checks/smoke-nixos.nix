# Smoke-eval the nixos preset chain (base -> bare-metal -> desktop), which pulls
# in the nixos modules those presets use. Instantiating it forces the module
# bodies to run, so `abort-on-warn` in CI catches deprecation warnings at the
# source instead of only once a consumer builds a system.
{
  inputs,
  self,
  system,
}:

let
  # Presets reference `inputs.dotless.*` from the consumer's namespace; inside
  # dotless itself, `dotless` is just `self`.
  ciInputs = inputs // {
    dotless = self;
  };
  profile = import ./profile.nix;
in
(inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inputs = ciInputs;
    inherit profile;
  };

  modules = [
    self.nixosModules.desktop
    {
      # Minimal hardware so `toplevel` evaluates. bare-metal already enables
      # systemd-boot; provide the mounts the boot loader assertions expect.
      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };
      fileSystems."/boot" = {
        device = "/dev/disk/by-label/ESP";
        fsType = "vfat";
      };
      system.stateVersion = "24.05";
    }
  ];
}).config.system.build.toplevel
