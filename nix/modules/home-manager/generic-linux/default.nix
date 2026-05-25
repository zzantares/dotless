{
  inputs,
  lib,
  pkgs,
  profile,
  ...
}:

# This module is only meant to be used in non-NixOS systems (i.e. generic linux distros)

{
  home.sessionVariables = {
    # So that CLI tools can use any locale other than "C"
    LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
  };

  home.shellAliases = {
    # Quickly allow to disable the builtin keyboard (useful when using an external keyboard)
    kbdisable = "xinput disable 12";
    kbenable = "xinput enable 12";
  };

  targets.genericLinux = {
    enable = true;

    # This instructs the HM nixGL module to actually use nixGL rather than bypass it
    nixGL.packages = inputs.nixGL.packages;
  };

  # TODO is this necessary? the nix module does this?
  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    # See: https://nix.dev/manual/nix/2.28/advanced-topics/cores-vs-jobs.html
    cores = 4; # Number of cores a single derivation build process is able to use
    max-jobs = 5; # Number of parallel builds that should be performed
  };

  # Gnome customizations
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      font-name = "Overpass 13";
      document-font-name = "Overpass Light 13";
      monospace-font-name = "JetBrains Mono 15";
      titlebar-font = "Overpass Bold 13";
      # This is equivalent to enabling the Accessibility "Large Text" toggle
      # we may enable this but only when no external display is attached
      # text-scaling-factor = 1.15;
    };

    # Dock on the right so that it is not in the midle of the displays
    "org/gnome/shell/extensions/dash-to-dock" = {
      dock-position = "RIGHT";
    };

    "org/gnome/desktop/peripherals/mouse" = {
      speed = lib.mkForce 0.35; # We might want this only when an external display is attached
    };
  };

  programs.ssh = {
    matchBlocks = {
      "*.local" = {
        user = profile.login;
      };
    };
  };
}
