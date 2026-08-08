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
    enable = lib.mkDefault true;
    package = lib.mkDefault pkgs.emacs;
    extraPackages =
      epkgs: with epkgs; [
        vterm
        treesit-grammars.with-all-grammars
      ];
  };

  services.emacs = lib.mkIf pkgs.stdenv.isLinux {
    enable = lib.mkDefault true;
    package = config.programs.emacs.package;

    # Pin the daemon's user-emacs-directory to Doom's XDG dir. Emacs otherwise
    # uses ~/.emacs.d as user-emacs-directory whenever that directory exists —
    # and this daemon (WantedBy=default.target, so it starts at login) comes up
    # before Doom is ever installed with `just emacs-install`, falls back to
    # ~/.emacs.d and creates it. That empty dir then permanently shadows Doom at
    # ~/.config/emacs, so emacsclient frames come up as stock Emacs. Passing
    # --init-directory (Emacs 29+) makes the resolution explicit and independent
    # of ~/.emacs.d's existence or daemon-vs-install start order.
    extraOptions = [ "--init-directory=${config.xdg.configHome}/emacs" ];
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
