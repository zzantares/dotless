# dotless

A composable, opinionated Home Manager and NixOS distribution. Think of it as
the [Doom Emacs](https://github.com/doomemacs/doomemacs) of dotfiles: batteries
included, but designed to be extended with your own private layer.

## What it provides

- **Presets** — composable role bundles (`base`, `devstation`, `workstation`)
- **Modules** — individual Home Manager modules you can opt into à la carte
- **NixOS modules** — system-level configuration (sops, gnome, kde, nix daemon)
- **Overlay** — curated toolchain groupings (haskell, rust, python, ops, etc.)
- **Lib** — flake discovery utilities (`discoverHome`, `discoverDarwin`, `discoverNixos`)

## Usage

Add dotless as a flake input:

```nix
inputs.dotless.url = "codeberg.org/youruser/dotless";

# Pin inputs to dotless's versions to avoid version mismatches
inputs.nixpkgs.follows = "dotless/nixpkgs";
inputs.home-manager.follows = "dotless/home-manager";
inputs.zsh-hist.follows = "dotless/zsh-hist";
inputs.t.follows = "dotless/t";
inputs.sops-nix.follows = "dotless/sops-nix";       # required by sops modules
inputs.nixGL.follows = "dotless/nixGL";              # required by generic-linux module
```

Apply the overlay and import a preset in your home configuration:

```nix
# flake.nix
nixpkgs.overlays = [ inputs.dotless.overlays.default ];

# home.nix
{ inputs, profile, ... }:
{
  imports = [ inputs.dotless.homeManagerModules.devstation ];
}
```

## The `profile` interface

All dotless modules receive a `profile` specialArg that carries your private
configuration. Your flake defines this and passes it via `specialArgs`:

```nix
specialArgs = {
  inherit inputs;
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
