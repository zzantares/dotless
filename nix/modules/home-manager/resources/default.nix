{ config, inputs, ... }:

{
  xdg.dataFile.fonts = {
    enable = true;
    source = "${inputs.self}/resources/fonts";
    target = "fonts";
    onChange = "/usr/bin/fc-cache -f -v";
  };

  xdg.dataFile.icons = {
    enable = true;
    source = "${inputs.self}/resources/icons";
    target = "icons";
    # NOTE this seems to work fine but keep in mind icons are linked to
    #   ~/.local/share/icons instead of ~/.nix-profile/share/icons
    onChange = "/usr/sbin/update-icon-caches ${config.home.homeDirectory}/.nix-profile/share/icons";
  };
}
