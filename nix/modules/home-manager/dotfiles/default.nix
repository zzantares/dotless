{
  profile,
  config,
  lib,
  ...
}:

# TODO Some/most of these files should be contained along with the toolchain that uses them (via a preset or smth)
# TODO Some of the symlinked configuration if stable should be made declarative (static)

{
  # This is configured as a symlink to not have to re-build HM whenever we change scripts
  home.file.bin = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${profile.flakeRoot}/src/bin";
    target = "${config.home.homeDirectory}/.local/bin";
  };

  # Ensure after switch that bin scripts are executable
  # chmod +x ${config.home.homeDirectory}/${profile.flakeRoot}/src/bin/*
  home.activation.makeLocalBinExecutables = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    chmod +x ${config.home.homeDirectory}/.local/bin/*
  '';

  # This is configured as a symlink to not have to re-build HM to change Emacs config
  home.file.doom = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${profile.flakeRoot}/config/doom";
    target = "${config.xdg.configHome}/doom";
  };

  # This is configured as a symlink to not have to re-build HM to change NeoVim config
  home.file.nvim = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${profile.flakeRoot}/config/nvim";
    target = "${config.xdg.configHome}/nvim";
  };

  # This is configured as a symlink to not have to re-build HM to change LazyVim config
  home.file.lazyvim = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${profile.flakeRoot}/config/lazyvim";
    target = "${config.xdg.configHome}/lazyvim";
  };

  # Configured as a symlink for rapid Nyxt iteration
  home.file.nyxt = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${profile.flakeRoot}/config/nyxt";
    target = "${config.xdg.configHome}/nyxt";
  };

  # Configured as a symlink for rapid Zed iteration
  home.file.zed = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${profile.flakeRoot}/config/zed";
    target = "${config.xdg.configHome}/zed";
  };

  # Configured as a symlink for rapid SBCL iteration
  home.file.sbclrc = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${profile.flakeRoot}/config/.sbclrc";
    target = "${config.home.homeDirectory}/.sbclrc";
  };

  home.file.clang-format = {
    enable = profile.user != "jgutierrez";
    source = ./.clang-format;
    target = ".clang-format";
  };

  home.file.clangd = {
    enable = profile.user != "jgutierrez";
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${profile.flakeRoot}/config/clangd";
    target = "${config.xdg.configHome}/clangd";
  };

  home.file.ghci = {
    enable = true;
    source = ./.ghci;
    target = ".ghci";
  };

  home.file.cabal = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${profile.flakeRoot}/config/cabal";
    target = "${config.xdg.configHome}/cabal";
  };

  home.file.stack = {
    enable = true;
    source = ./stack-config.yaml;
    target = ".stack/config.yaml";
    force = true; # Replace the backup file if one is already there
  };

  home.file.haskeline = {
    enable = true;
    source = ./.haskeline;
    target = ".haskeline";
  };

  home.file.lesskey = {
    enable = true;
    source = ./.lesskey;
    target = ".lesskey";
  };

  home.file.mosx = {
    enable = false;
    source = ./.mosx;
    target = ".mosx";
  };

  home.file.psqlrc = {
    enable = true;
    source = ./.psqlrc;
    target = ".psqlrc";
  };

  home.file.tridactyl = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${profile.flakeRoot}/config/tridactyl";
    target = "${config.xdg.configHome}/tridactyl";
  };
}
