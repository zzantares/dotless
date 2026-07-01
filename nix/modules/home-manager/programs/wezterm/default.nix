{
  config,
  lib,
  pkgs,
  ...
}:

{
  programs.wezterm = {
    enable = lib.mkDefault true;
    package = if pkgs.stdenv.isDarwin then pkgs.wezterm else config.lib.nixGL.wrap pkgs.wezterm;

    enableZshIntegration = lib.mkDefault true;
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
