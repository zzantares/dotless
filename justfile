flake-update:
    #!/usr/bin/env bash
    set -euo pipefail

    nixos_status="$(xh 'https://prometheus.nixos.org/api/v1/query?query=channel_revision')"

    nixpkgs_branch="nixos-unstable"
    home_branch="master"
    darwin_branch="master"

    nixpkgs_release=$(jq -r --arg NIXPKGS_BRANCH "$nixpkgs_branch" '
        .data.result[].metric
        | select(.channel==$NIXPKGS_BRANCH and (.status=="rolling" or .status=="stable"))
        | .revision' <<< "$nixos_status")

    home_release=$(git ls-remote "git@github.com:nix-community/home-manager.git" "refs/heads/$home_branch" | awk '{ print $1; }')
    darwin_rev=$(git ls-remote "git@github.com:nix-darwin/nix-darwin.git" "refs/heads/$darwin_branch" | awk '{ print $1; }')

    # The flake inputs to update
    nixpkgs_input="nixpkgs"
    home_input="home-manager"
    darwin_input="nix-darwin"

    echo "Updated revisions:"
    echo -e "    ${nixpkgs_input}\t\t${nixpkgs_branch}\t${nixpkgs_release}"
    echo -e "    ${home_input}\t${home_branch}\t${home_release}"
    echo -e "    ${darwin_input}\t${darwin_branch}\t${darwin_rev}"

    if [[ -z "$nixpkgs_release" || -z "$home_release" || -z "$darwin_rev" ]]; then
        echo "ERROR: Unable to fetch revisions"
        exit
    fi

    # Update the stable revision
    sed -i "s/# ${nixpkgs_branch} at.*/# ${nixpkgs_branch} at $(date +%Y-%m-%d)/g" flake.nix
    sed -i "s/${nixpkgs_input}.url = \"github:NixOS\/nixpkgs?rev=[a-zA-Z0-9]*\"/${nixpkgs_input}.url = \"github:NixOS\/nixpkgs?rev=${nixpkgs_release}\"/" flake.nix

    # Update the home revision
    sed -i "s/# ${home_branch} at.*/# ${home_branch} at $(date +%Y-%m-%d)/g" flake.nix
    sed -i "s/${home_input}.url = \"github:nix-community\/home-manager?rev=[a-zA-Z0-9]*\"/${home_input}.url = \"github:nix-community\/home-manager?rev=${home_release}\"/" flake.nix

    # Update the nix-darwin revision
    sed -i "s/# ${darwin_branch} at.*/# ${darwin_branch} at $(date +%Y-%m-%d)/g" flake.nix
    sed -i "s/${darwin_input}.url = \"github:nix-darwin\/nix-darwin?rev=[a-zA-Z0-9]*\"/${darwin_input}.url = \"github:nix-darwin\/nix-darwin?rev=${darwin_rev}\"/" flake.nix

    # Regenerate the lock file and update non-pinned inputs
    nix flake update

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
