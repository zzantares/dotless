{
  profile,
  config,
  pkgs,
  lib,
  ...
}:

{
  # TODO Should look into keeping these files on the dotfiles repo
  # - per-machine projects: projectile-known-projects-file (~/.config/emacs/.local/cache/projectile.projects)
  # - custom dictionary: spell-fu-directory (~/.config/emacs/.local/etc/spell-fu)
  programs.emacs = {
    enable = true;
    package = pkgs.emacs;
    extraPackages =
      epkgs: with epkgs; [
        vterm
        treesit-grammars.with-all-grammars
      ];
  };

  services.emacs = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    package = config.programs.emacs.package;
  };

  systemd.user.services.emacs.Service.Environment = lib.mkIf pkgs.stdenv.isLinux [
    "DOTFILES_FLAKE_ROOT=${config.home.homeDirectory}/${profile.flakeRoot}"
  ];

  # Add our own desktop entry in order to use Emacs Doom icon
  xdg.desktopEntries.emacs = lib.mkIf pkgs.stdenv.isLinux {
    name = "Emacs";
    genericName = "Text Editor";
    comment = "An extensible, customizable, free/libre text editor";
    type = "Application";
    exec = "emacsclient -c -a emacs %F";
    icon = "doom";
    terminal = false;

    settings = {
      StartupWMClass = "Emacs";
    };

    categories = [
      "Development"
      "TextEditor"
    ];

    mimeType = [
      "text/english"
      "text/plain"
      "text/x-makefile"
      "text/x-c++hdr"
      "text/x-c++src"
      "text/x-chdr"
      "text/x-csrc"
      "text/x-java"
      "text/x-moc"
      "text/x-pascal"
      "text/x-tcl"
      "text/x-tex"
      "application/x-shellscript"
      "text/x-c"
      "text/x-c++"
    ];
  };
}
