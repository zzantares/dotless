{
  config,
  lib,
  pkgs,
  ...
}:

let
  wezterm = config.programs.wezterm.package;

  tw = pkgs.writeShellScriptBin "t" ''
    set -euo pipefail

    # 1. Resolve target directory
    if [ $# -gt 0 ]; then
      dir=$(${pkgs.zoxide}/bin/zoxide query "$@") || exit 1
    else
      dir=$(${pkgs.zoxide}/bin/zoxide query -l \
        | ${pkgs.fzf}/bin/fzf --reverse --preview 'ls -1 --color=always {}') || exit 0
    fi

    # 2. Derive workspace name (git root basename when possible)
    git_root=$(${pkgs.git}/bin/git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
    base_dir="''${git_root:-$dir}"
    ws_name="''${base_dir##*/}"

    # 3. Switch to (or create) the workspace.
    #
    # WezTerm's CLI cannot change the active workspace — only the GUI can, via the
    # SwitchToWorkspace action. So hand the request to the GUI through a user var
    # (OSC 1337 SetUserVar named "switch-workspace", value = base64 of
    # "<name>\t<cwd>"). The wezterm.lua `user-var-changed` handler performs the
    # actual switch. This works when `t` is run inside a WezTerm pane.
    if [ -n "''${WEZTERM_PANE:-}" ]; then
      payload=$(printf '%s\t%s' "$ws_name" "$dir" | ${pkgs.coreutils}/bin/base64 | tr -d '\n')
      osc=$(printf '\033]1337;SetUserVar=switch-workspace=%s\a' "$payload")
      esc=$(printf '\033')
      if [ -n "''${TMUX:-}" ]; then
        # Inside tmux: wrap for passthrough (needs `set -g allow-passthrough on`),
        # doubling every ESC in the inner sequence.
        printf '\033Ptmux;%s\033\\' "''${osc//$esc/$esc$esc}" > /dev/tty
      else
        printf '%s' "$osc" > /dev/tty
      fi
    elif ${wezterm}/bin/wezterm cli list >/dev/null 2>&1; then
      # A mux is running but we're not inside a WezTerm pane — best effort: create
      # the workspace in a new window (focus may not follow; use CTRL+t T to switch).
      ${wezterm}/bin/wezterm cli spawn --new-window --workspace "$ws_name" --cwd "$dir" >/dev/null
    else
      # No running instance — start one in the target workspace.
      ${wezterm}/bin/wezterm start --workspace "$ws_name" --cwd "$dir"
    fi
  '';
in
{
  home.packages = [ tw ];

  programs.wezterm = {
    enable = lib.mkDefault true;
    package = if pkgs.stdenv.isDarwin then pkgs.wezterm else config.lib.nixGL.wrap pkgs.wezterm;

    enableZshIntegration = lib.mkDefault true;

    extraConfig = lib.mkDefault (builtins.readFile ./../../../../../config/wezterm/wezterm.lua);
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
