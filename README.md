# dotless

A composable, opinionated Home Manager and NixOS distribution. Think of it as
the [Doom Emacs](https://github.com/doomemacs/doomemacs) of dotfiles: batteries
included, but designed to be extended with your own private layer.

> [!WARNING]
> this part of my personal dotfiles configuration, therefore expect this to be
> opinionated, unstable, or broken at times.

## What it provides

- **Home Manager presets** — composable role bundles (`base`, `devstation`, `workstation`, `server`)
- **Home Manager modules** — individual modules you can opt into à la carte (`git`, `zsh`, `ssh`, `sops`, `emacs`, …)
- **NixOS presets** — system-level role bundles (`base`, `bare-metal`, `server`, `desktop`, `node`)
- **NixOS modules** — opt-in system services (`sops`, `syncthing`, `tailscale`, `gnome`, `kde`) and an opt-in nix daemon module (`nix`) usable on any platform
- **nix-darwin presets** — system-level foundation (`base`) that unblocks Home Manager integration
- **Overlay** — curated toolchain groupings (`haskell`, `rust`, `python`, `ops`, `network`, …) and the [`pr-review`](nix/pkgs/emacs/pr-review/README.md) Emacs package
- **Lib** — flake discovery utilities (`discoverHome`, `discoverDarwin`, `discoverNixos`)

## Setup

### Add dotless as a flake input

Your flake owns the pins for foundational inputs; dotless follows them.
This ensures a single unified nixpkgs evaluation across your whole system.

```nix
# Your flake owns these pins
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

inputs.home-manager.url = "github:nix-community/home-manager";
inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

inputs.sops-nix.url = "github:Mic92/sops-nix";          # required by sops modules
inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";

inputs.nixGL.url = "github:nix-community/nixGL";         # required by generic-linux module
inputs.nixGL.inputs.nixpkgs.follows = "nixpkgs";

# nix-darwin users only:
# inputs.nix-darwin.url = "github:nix-darwin/nix-darwin";
# inputs.nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

# dotless follows your pins
inputs.dotless.url = "codeberg.org/youruser/dotless";
inputs.dotless.inputs.nixpkgs.follows      = "nixpkgs";
inputs.dotless.inputs.home-manager.follows = "home-manager";
inputs.dotless.inputs.sops-nix.follows     = "sops-nix";
inputs.dotless.inputs.nixGL.follows        = "nixGL";
# inputs.dotless.inputs.nix-darwin.follows = "nix-darwin";  # nix-darwin users only

# dotless-internal source inputs — follow dotless
inputs.t.follows       = "dotless/t";
inputs.zsh-hist.follows = "dotless/zsh-hist";
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
    inputs.dotless.homeModules.devstation
  ];
}
```

Optionally include the nix module for opinionated nix daemon configuration
(experimental features, binary caches, registry pinning):

```nix
modules = [
  { nixpkgs.overlays = [ inputs.dotless.overlays.default ]; }
  inputs.dotless.nixosModules.nix      # opt-in: manages the nix daemon
  inputs.dotless.homeModules.devstation
];
```

> **Note:** `nixosModules.nix` works in both the HM module system and the
> NixOS/nix-darwin system module system — import it wherever is appropriate
> for your setup (see the NixOS and nix-darwin sections below).

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
        inputs.dotless.homeModules.devstation
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

Optionally include the nix module for opinionated nix daemon configuration
(binary caches, registry pinning, experimental features). Import it at the
system level so nix is configured once for the whole machine, not per user:

```nix
nixpkgs.lib.nixosSystem {
  specialArgs = { inherit inputs profile; };
  modules = [
    ./hardware-configuration.nix
    inputs.dotless.nixosModules.bare-metal
    inputs.dotless.nixosModules.nix          # opt-in: system-level nix config
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager.extraSpecialArgs = { inherit inputs profile; };
      home-manager.users.${profile.login}.imports = [
        inputs.dotless.homeModules.devstation
      ];
    }
  ];
}
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
        inputs.dotless.homeModules.devstation
      ];
    }
  ];
}
```

Optionally include the nix module for opinionated nix daemon configuration
(binary caches, registry pinning, experimental features). Import it at the
system level so nix is configured once for the whole machine, not per user:

```nix
nix-darwin.lib.darwinSystem {
  specialArgs = { inherit inputs profile; };
  modules = [
    inputs.dotless.darwinModules.base
    inputs.dotless.nixosModules.nix          # opt-in: system-level nix config
    inputs.home-manager.darwinModules.home-manager
    {
      home-manager.extraSpecialArgs = { inherit inputs profile; };
      home-manager.users.${profile.login}.imports = [
        inputs.dotless.homeModules.devstation
      ];
    }
  ];
}
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

## Secrets

dotless uses [sops-nix](https://github.com/Mic92/sops-nix) for secret management. Secrets are
read from your own flake at:

```
${inputs.self}/secrets/${profile.login}/secrets.yaml
```

The file must be encrypted with the keys configured in your `.sops.yaml`. dotless itself never
ships secrets — the file lives in your private repo.

The Home Manager sops module decrypts using GPG (`~/.gnupg`). The NixOS sops module uses age,
deriving keys from your SSH host key (`/etc/ssh/ssh_host_ed25519_key`) and your profile SSH key
(`~/.ssh/id_ed25519`).

### Secret inventory

All secrets are conditional — they are only required when the module that needs them is enabled.
If you hit a `key cannot be found` error, either populate the secret or disable the relevant module.

| Secret key | Required when | Purpose |
|---|---|---|
| `openrouter_api_key` | `programs.opencode.enable = true` (default on) | OpenRouter API key used by opencode and the `q` (qwen-code) alias |
| `github_auth_token` | `programs.opencode.enable = true` (default on) | GitHub personal access token exported as `GITHUB_TOKEN` |
| `forgejo_mcp_token` | `programs.claude-code.enable = true` (default on supported platforms) | Access token for the Forgejo MCP server |

**To opt out of a secret**, disable the module that requires it:

```nix
# disable all three secrets
programs.claude-code.enable = false;
programs.opencode.enable    = false;

# disable only the forgejo token
programs.claude-code.enable = false;

# disable only the openrouter + github tokens
programs.opencode.enable = false;
```

**Minimum `secrets.yaml` structure** (when all modules are enabled):

```yaml
openrouter_api_key: <your OpenRouter API key>
github_auth_token: <your GitHub personal access token>
forgejo_mcp_token: <your Forgejo access token>
```

## Extending dotless

Use `disabledModules` to opt out of any sub-module:

```nix
disabledModules = [ inputs.dotless.homeModules."claude-code" ];
```

Add your own private modules alongside dotless ones:

```nix
imports = [
  inputs.dotless.homeModules.devstation
  ./my-private-module.nix
];
```

Override any option using the standard NixOS module system:

```nix
programs.git.settings.github.user = lib.mkForce "my-github-user";
```

## License

GNU General Public License v3.0 or later — see [LICENSE](LICENSE).
