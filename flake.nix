{
  description = "dotless - a composable Home Manager and NixOS distribution";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:nix-darwin/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    nixGL.url = "github:nix-community/nixGL";
    nixGL.inputs.nixpkgs.follows = "nixpkgs";

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay.url = "github:oxalica/rust-overlay";

    nur.url = "github:nix-community/NUR";

    plasma-manager.url = "github:nix-community/plasma-manager";
    plasma-manager.inputs.nixpkgs.follows = "nixpkgs";
    plasma-manager.inputs.home-manager.follows = "home-manager";

    # ZSH plugin to manipulate zsh history file (for failed cmd hook history removal)
    zsh-hist.url = "github:marlonrichert/zsh-hist";
    zsh-hist.flake = false;

    t.url = "github:joshmedeski/t-smart-tmux-session-manager?ref=v2.11.1";
    t.flake = false;

    zed-editor.url = "github:zed-industries/zed?ref=v1.9.0";
    zed-editor.inputs.nixpkgs.follows = "nixpkgs";

    opencode.url = "github:anomalyco/opencode?ref=v1.14.48";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }@inputs:
    let
      lib = nixpkgs.lib.extend (
        final: prev: {
          zz = import ./nix/lib { lib = prev; };
        }
      );
    in
    {
      inherit lib;

      overlays.default = nixpkgs.lib.composeManyExtensions [
        (import ./nix/overlays { inherit inputs; })
        inputs.rust-overlay.overlays.default
        inputs.nur.overlays.default
      ];

      # Presets: batteries-included bundles suitable for most users.
      # Import one of these as a starting point and override/extend as needed.
      homeModules = {
        base = ./nix/presets/home-manager/base;
        devstation = ./nix/presets/home-manager/devstation;
        workstation = ./nix/presets/home-manager/workstation;

        # Individual modules — opt in à la carte
        git = ./nix/modules/home-manager/programs/git;
        zsh = ./nix/modules/home-manager/programs/zsh;
        zsh-bare = ./nix/modules/home-manager/programs/zsh-bare;
        tmux = ./nix/modules/home-manager/programs/tmux;
        bat = ./nix/modules/home-manager/programs/bat;
        alacritty = ./nix/modules/home-manager/programs/alacritty;
        emacs = ./nix/modules/home-manager/programs/emacs;
        fourmolu = ./nix/modules/home-manager/programs/fourmolu;
        "claude-code" = ./nix/modules/home-manager/programs/claude-code;
        ssh = ./nix/modules/home-manager/programs/ssh;
        browser = ./nix/modules/home-manager/programs/browser;
        firefox = ./nix/modules/home-manager/programs/firefox;
        librewolf = ./nix/modules/home-manager/programs/librewolf;
        jujutsu = ./nix/modules/home-manager/programs/jujutsu;
        dotfiles = ./nix/modules/home-manager/dotfiles;
        email = ./nix/modules/home-manager/email;
        sops = ./nix/modules/home-manager/sops;
        gnome = ./nix/modules/home-manager/gnome;
        kde = ./nix/modules/home-manager/kde;
        hyprland = ./nix/modules/home-manager/hyprland;
        xmonad = ./nix/modules/home-manager/xmonad;
        streaming = ./nix/modules/home-manager/streaming;
        "generic-linux" = ./nix/modules/home-manager/generic-linux;
      };

      # NixOS-level modules and presets — for system configuration (not home-manager)
      nixosModules = {
        # Individual opt-in modules
        nix = ./nix/modules/nix;
        sops = ./nix/modules/nixos/sops;
        gnome = ./nix/modules/nixos/gnome;
        kde = ./nix/modules/nixos/kde;
        cosmic = ./nix/modules/nixos/cosmic;
        hyprland = ./nix/modules/nixos/hyprland;
        syncthing = ./nix/modules/nixos/syncthing;
        tailscale = ./nix/modules/nixos/tailscale;

        # Presets: batteries-included bundles for common machine roles.
        # base — foundation for all managed NixOS systems
        # bare-metal — extends base with user creation, firewall, boot loader
        # server — bare-metal + node networking (no desktop, no wireless)
        # desktop — bare-metal + NetworkManager + wireless
        # node — compute-oriented networking + optional auto-upgrade (set profile.flakeUrl)
        base = ./nix/presets/nixos/base;
        bare-metal = ./nix/presets/nixos/bare-metal;
        server = ./nix/presets/nixos/server;
        desktop = ./nix/presets/nixos/desktop;
        node = ./nix/presets/nixos/node;
      };

      # nix-darwin-level modules and presets — for system configuration (not home-manager)
      darwinModules = {
        # base — foundation for all managed nix-darwin systems; sets
        # users.users.${profile.login}.home so home-manager can derive
        # home.homeDirectory correctly when used as a nix-darwin module.
        base = ./nix/presets/darwin/base;
      };
    }
    //
      flake-utils.lib.eachSystem
        [
          "x86_64-linux"
          "aarch64-darwin"
        ]
        (
          system:
          let
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
              overlays = [ self.overlays.default ];
            };
          in
          {
            formatter = pkgs.nixfmt-tree;

            # Expose overlay packages for local testing: `nix build .#claude-code`
            packages = {
              inherit (pkgs)
                claude-code
                opencode
                fonts
                wallpapers
                linear-cli
                zed-editor
                ;
            };
          }
        );
}
