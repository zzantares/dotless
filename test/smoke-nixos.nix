# Instantiate the nixos preset chain (desktop) so its modules' warnings surface
# under abort-on-warn.
{
  inputs,
  self,
  system,
}:

let
  # presets reference inputs.dotless; here dotless is self.
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
      # minimal hardware so toplevel evaluates (bare-metal enables systemd-boot).
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
