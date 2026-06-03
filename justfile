# Route to the correct platform-specific check recipe.
check:
    just check-{{ if os() == "macos" { "darwin" } else { "linux" } }}

# Check that the devstation preset builds cleanly as a standalone home-manager
# configuration on Linux (x86_64-linux).
check-linux:
    #!/usr/bin/env bash
    nix --extra-experimental-features "nix-command flakes" build --impure --expr '
      let
        flake = builtins.getFlake (toString ./.);
        hm = flake.inputs.home-manager;
        profile = {
          login = "test";
          flakeRoot = "config";
          shellAliases = {};
          email = "test@example.com";
          emailAddresses = [ "test@example.com" ];
          name = "Test User";
          user = "test";
          alacrittyColors = "yorumi-abyss";
          sshKeys = [];
          identityFile = ".ssh/id_ed25519";
          ohMyZshTheme = "robbyrussell";
        };
        # The sops module references inputs.self; dotless points back at this
        # flake when checked in-tree.
        inputs = flake.inputs // { self = flake; dotless = flake; };
      in
        (hm.lib.homeManagerConfiguration {
          pkgs = import flake.inputs.nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
            overlays = [ flake.overlays.default ];
          };
          extraSpecialArgs = { inherit inputs profile; };
          modules = [
            flake.homeManagerModules.devstation
            {
              home.username = profile.login;
              home.homeDirectory = "/home/${profile.login}";
              home.stateVersion = "24.11";
              sops.validateSopsFiles = false;
            }
          ];
        }).activationPackage
    '

# Check that the devstation preset builds cleanly as a nix-darwin
# configuration that drives home-manager via darwinModules.home-manager.
check-darwin:
    #!/usr/bin/env bash
    nix --extra-experimental-features "nix-command flakes" build --impure --expr '
      let
        flake = builtins.getFlake (toString ./.);
        darwin = flake.inputs.nix-darwin;
        hm = flake.inputs.home-manager;
        profile = {
          login = "test";
          flakeRoot = "config";
          shellAliases = {};
          email = "test@example.com";
          emailAddresses = [ "test@example.com" ];
          name = "Test User";
          user = "test";
          alacrittyColors = "yorumi-abyss";
          sshKeys = [];
          identityFile = ".ssh/id_ed25519";
          ohMyZshTheme = "robbyrussell";
        };
        # The darwin base preset references inputs.dotless.overlays.default and
        # the sops module references inputs.self; both point back at this flake
        # when checked in-tree.
        inputs = flake.inputs // { self = flake; dotless = flake; };
      in
        (darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = { inherit inputs profile; };
          modules = [
            flake.darwinModules.base
            hm.darwinModules.home-manager
            {
              system.stateVersion = 5;
              system.primaryUser = profile.login;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs profile; };
              home-manager.users.${profile.login} = {
                imports = [ flake.homeManagerModules.devstation ];
                home.stateVersion = "24.11";
                sops.validateSopsFiles = false;
              };
            }
          ];
        }).system
    '
