# dotless

A composable, opinionated Home Manager and NixOS distribution. Think of it as
the [Doom Emacs](https://github.com/doomemacs/doomemacs) of dotfiles: batteries
included, but designed to be extended with your own private layer.

## What it provides

- **Home Manager presets** — composable role bundles (`base`, `devstation`, `workstation`, `server`)
- **Home Manager modules** — individual modules you can opt into à la carte (`git`, `zsh`, `ssh`, `sops`, `emacs`, …)
- **NixOS presets** — system-level role bundles (`base`, `bare-metal`, `server`, `desktop`, `node`)
- **NixOS modules** — opt-in system services (`sops`, `syncthing`, `tailscale`, `gnome`, `kde`) and an opt-in nix daemon module (`nix`) usable on any platform
- **nix-darwin presets** — system-level foundation (`base`) that unblocks Home Manager integration
- **Overlay** — curated toolchain groupings (`haskell`, `rust`, `python`, `ops`, `network`, …)
- **Lib** — flake discovery utilities (`discoverHome`, `discoverDarwin`, `discoverNixos`)

## Setup

### Add dotless as a flake input

```nix
inputs.dotless.url = "codeberg.org/youruser/dotless";

# Pin inputs to dotless's versions to avoid version mismatches
inputs.nixpkgs.follows        = "dotless/nixpkgs";
inputs.home-manager.follows   = "dotless/home-manager";
inputs.zsh-hist.follows       = "dotless/zsh-hist";
inputs.t.follows              = "dotless/t";
inputs.sops-nix.follows       = "dotless/sops-nix";   # required by sops modules
inputs.nixGL.follows          = "dotless/nixGL";        # required by generic-linux module
inputs.nix-darwin.follows     = "dotless/nix-darwin";  # nix-darwin users only
```

### Standalone Home Manager

For generic Linux or macOS without NixOS or nix-darwin:

```nix
# flake.nix
home-manager.lib.homeManagerConfiguration {
  pkgs = nixpkgs.legacyPackages.${system};
  extraSpecialArgs = { inherit inputs profile; };
  modules = [
    { nixpkgs.overlays = [ inputs.dotless.overlays.default ]; }
    inputs.dotless.homeManagerModules.devstation
  ];
}
```

Optionally include the nix module to get an opinionated nix daemon
configuration (experimental features, binary caches, registry pinning):

```nix
modules = [
  { nixpkgs.overlays = [ inputs.dotless.overlays.default ]; }
  inputs.dotless.nixosModules.nix      # opt-in: manages the nix daemon
  inputs.dotless.homeManagerModules.devstation
];
```

### NixOS + Home Manager

The NixOS presets create the system user and apply the overlay automatically.
Home Manager derives `home.homeDirectory` from `users.users.${login}.home`,
which the `bare-metal` preset sets correctly.

```nix
# flake.nix
nixpkgs.lib.nixosSystem {
  specialArgs = { inherit inputs profile; };
  modules = [
    ./hardware-configuration.nix
    inputs.dotless.nixosModules.bare-metal   # or server / desktop
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager.extraSpecialArgs = { inherit inputs profile; };
      home-manager.users.${profile.login}.imports = [
        inputs.dotless.homeManagerModules.devstation
      ];
    }
  ];
}
```

Optional system-level modules to compose in:

```nix
imports = [
  inputs.dotless.nixosModules.sops       # age/sops secret decryption
  inputs.dotless.nixosModules.syncthing  # Syncthing file sync service
  inputs.dotless.nixosModules.tailscale  # Tailscale VPN
  inputs.dotless.nixosModules.gnome      # GNOME desktop environment
  inputs.dotless.nixosModules.kde        # KDE Plasma desktop environment
];
```

Optionally include the nix module in your Home Manager config for an opinionated
nix daemon configuration (binary caches, registry pinning, experimental features).
On NixOS it defers daemon management to the system and only applies user-level
nix settings:

```nix
home-manager.users.${profile.login}.imports = [
  inputs.dotless.nixosModules.nix        # opt-in: opinionated nix settings
  inputs.dotless.homeManagerModules.devstation
];
```

### nix-darwin + Home Manager

The `darwinModules.base` preset sets `users.users.${login}.home` so that
Home Manager can correctly derive `home.homeDirectory` when used as a
nix-darwin module.

```nix
# flake.nix
nix-darwin.lib.darwinSystem {
  specialArgs = { inherit inputs profile; };
  modules = [
    inputs.dotless.darwinModules.base
    inputs.home-manager.darwinModules.home-manager
    {
      home-manager.extraSpecialArgs = { inherit inputs profile; };
      home-manager.users.${profile.login}.imports = [
        inputs.dotless.homeManagerModules.devstation
      ];
    }
  ];
}
```

Optionally include the nix module in your Home Manager config for an opinionated
nix daemon configuration (binary caches, registry pinning, experimental features).
On nix-darwin it defers daemon management to the system and only applies
user-level nix settings:

```nix
home-manager.users.${profile.login}.imports = [
  inputs.dotless.nixosModules.nix        # opt-in: opinionated nix settings
  inputs.dotless.homeManagerModules.devstation
];
```

## The `profile` interface

All dotless modules receive a `profile` specialArg that carries your private
configuration. Your flake defines this and passes it via `specialArgs` or
`extraSpecialArgs`:

```nix
profile = {
  # Identity (required by most modules)
  name           = "Your Name";
  user           = "github-username";
  login          = "system-login";
  email          = "you@example.com";
  emailAddresses = [ "you@example.com" ];
  sshKeys        = [ "ssh-ed25519 AAAA... comment" ];
  identityFile   = ".ssh/id_ed25519.pub";
  flakeRoot      = "path/to/dotfiles/from/home";
  sensitive      = import ./secrets/myuser/sensitive.nix;

  # System configuration (optional)
  timeZone  = "America/New_York";  # sets time.timeZone on NixOS and nix-darwin
  flakeUrl  = "git+ssh://git@github.com/you/dotfiles";  # enables auto-upgrade on node preset

  # Private config consumed by specific modules
  sshMatchBlocks      = { "myserver" = { port = 2222; }; };
  gpgKey              = "FINGERPRINT";
  smtpTlsFingerprint  = "AA:BB:...";
  emailAfewRules      = "";
  shellAliases        = { terraform = "tofu"; };

  # Aesthetics (optional — dotless provides defaults)
  alacrittyColors  = "yorumi-abyss";
  gnomeAccentColor = "blue";
  ohMyZshTheme     = "sorin";
  wallpaper        = null;

  # User-provided resources (optional — used by the resources module)
  fontsPath      = null;  # "${inputs.self}/resources/fonts"
  wallpapersPath = null;  # "${inputs.self}/resources/wallpapers"
  iconsPath      = null;  # "${inputs.self}/resources/icons"
};
```

## Extending dotless

Use `disabledModules` to opt out of any sub-module:

```nix
disabledModules = [ inputs.dotless.homeManagerModules."claude-code" ];
```

Add your own private modules alongside dotless ones:

```nix
imports = [
  inputs.dotless.homeManagerModules.devstation
  ./my-private-module.nix
];
```

Override any option using the standard NixOS module system:

```nix
programs.git.settings.github.user = lib.mkForce "my-github-user";
```

## License

GNU General Public License v3.0 or later — see [LICENSE](LICENSE).
