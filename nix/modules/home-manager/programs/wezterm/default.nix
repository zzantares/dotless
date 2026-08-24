{
  profile,
  config,
  lib,
  pkgs,
  ...
}:

let
  # Convention: if the consumer sets profile.liveOverrides.wezterm, symlink their whole
  # config dir live (out-of-store → editable, auto-reloads, no rebuild, and split-into-
  # multiple-lua-files works). Otherwise bake dotless's bundled config into the store.
  #
  # DECLARED, not detected: this used to probe wezterm.lua with builtins.pathExists,
  # which is impure (needs --impure) and aborts eval in CI where the runner can't read
  # the user's home. TODO(dotless#48): pure, shared live-override mechanism.
  userDir = "${config.home.homeDirectory}/${profile.flakeRoot}/config/wezterm";
  hasUserConfig = profile.liveOverrides.wezterm or false;
in
{
  programs.wezterm = {
    enable = lib.mkDefault true;
    package =
      if pkgs.stdenv.hostPlatform.isDarwin then pkgs.wezterm else config.lib.nixGL.wrap pkgs.wezterm;

    enableZshIntegration = lib.mkDefault true;

    # Empty ⇒ the home-manager wezterm module writes no file, leaving ~/.config/wezterm
    # free for the directory symlink below (no collision).
    extraConfig =
      if hasUserConfig then
        ""
      else
        lib.mkDefault (builtins.readFile ./../../../../../config/wezterm/wezterm.lua);
  };

  # Consumer-provided config dir → live out-of-store symlink (the doom pattern).
  xdg.configFile."wezterm" = lib.mkIf hasUserConfig {
    source = config.lib.file.mkOutOfStoreSymlink userDir;
  };

  # WezTerm's shell integration emits OSC 1337 sequences (SetUserVar, semantic
  # zones, OSC 7 cwd) that only WezTerm consumes. Terminals that don't speak them
  # — most notably Emacs vterm — render them as visible junk. The integration is
  # sourced unconditionally by enableZshIntegration, so gate it here: every
  # WezTerm pane exports WEZTERM_PANE, so disable the integration wherever that
  # marker is absent. Also skip inside Emacs, because WEZTERM_PANE is inherited by
  # child processes: an Emacs launched from a WezTerm shell would otherwise leak
  # the stale marker into its vterm buffers. Set in .zshenv (envExtra) so it lands
  # before .zshrc sources wezterm.sh, which honors WEZTERM_SHELL_SKIP_ALL.
  programs.zsh.envExtra = ''
    if [[ -z "$WEZTERM_PANE" || -n "$INSIDE_EMACS" ]]; then
      export WEZTERM_SHELL_SKIP_ALL=1
    fi
  '';
}
