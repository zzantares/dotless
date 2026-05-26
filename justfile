# Check that the devstation preset builds cleanly
check:
    #!/usr/bin/env bash
    nix build --impure --expr '
      let
        flake = builtins.getFlake (toString ./.);
        hm = flake.inputs.home-manager;
        pkgs = import flake.inputs.nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
          overlays = [ flake.overlays.default ];
        };
      in
        (hm.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            flake.homeManagerModules.devstation
            {
              home.stateVersion = "24.11";
              sops.validateSopsFiles = false;
            }
          ];
          extraSpecialArgs = {
            inputs = flake.inputs // { self = flake; };
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
          };
        }).config.home.activationPackage
    '
