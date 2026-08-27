{
  profile,
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  enabled = config.programs.emacs.enable;

  # Doom's config.el reads this at init time. Neither systemd nor launchd sources
  # the shell, so home.sessionVariables never reaches the daemon.
  flakeRoot = "${config.home.homeDirectory}/${profile.flakeRoot}";
in

{
  # TODO Should look into keeping these files on the dotfiles repo
  # - per-machine projects: projectile-known-projects-file (~/.config/emacs/.local/cache/projectile.projects)
  # - custom dictionary: spell-fu-directory (~/.config/emacs/.local/etc/spell-fu)
  programs.emacs = {
    enable = lib.mkDefault true;

    # macOS gets the emacs-plus patch stack (NS window role, undecorated frame,
    # system appearance, Doom icon); Linux keeps stock Emacs, and the gnome
    # module swaps in emacs-pgtk on top of this default.
    package = lib.mkDefault (if isDarwin then pkgs.emacs-plus else pkgs.emacs);

    extraPackages =
      epkgs: with epkgs; [
        vterm
        treesit-grammars.with-all-grammars
      ];
  };

  # The daemon runs on both platforms: systemd user service on Linux, launchd
  # agent on darwin, both from home-manager's services.emacs. `package` is left
  # at its default, programs.emacs.finalPackage, so the daemon carries
  # extraPackages - pinning it to programs.emacs.package dropped them.
  services.emacs = {
    enable = lib.mkDefault enabled;

    # Pin the daemon's user-emacs-directory to Doom's XDG dir. Emacs falls back
    # to ~/.emacs.d whenever that exists, and the daemon starts at login - before
    # Doom is installed - creating it and permanently shadowing ~/.config/emacs.
    extraOptions = [ "--init-directory=${config.xdg.configHome}/emacs" ];
  };

  systemd.user.services.emacs.Service.Environment = lib.mkIf isLinux [
    "DOTFILES_FLAKE_ROOT=${flakeRoot}"
  ];

  launchd.agents.emacs.config = lib.mkIf (isDarwin && config.services.emacs.enable) {
    # Start the daemon through the .app bundle rather than bin/emacs: macOS reads
    # GUI app identity from the bundle, and the daemon's frames inherit it.
    ProgramArguments = lib.mkForce (
      [
        "${config.services.emacs.package}/Applications/Emacs.app/Contents/MacOS/Emacs"
        "--fg-daemon"
      ]
      ++ config.services.emacs.extraOptions
    );

    # Ask macOS for the interactive QoS scheduling tier.
    ProcessType = "Interactive";

    EnvironmentVariables = {
      DOTFILES_FLAKE_ROOT = flakeRoot;
    };
  };

  # The macOS counterpart of the desktop entry below: an applet that hands files
  # and org-protocol URLs to the daemon. Built against finalPackage so it calls
  # the emacsclient that carries extraPackages.
  home.packages = lib.mkIf (isDarwin && enabled) [
    (pkgs.emacs-client.override { emacs = config.programs.emacs.finalPackage; })
  ];

  # Add our own desktop entry in order to use Emacs Doom icon
  xdg.desktopEntries.emacs = lib.mkIf isLinux {
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
