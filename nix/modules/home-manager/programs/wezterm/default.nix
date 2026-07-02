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

    # 3. Launch or connect
    if ! ${wezterm}/bin/wezterm cli list >/dev/null 2>&1; then
      # No running instance — start one
      ${wezterm}/bin/wezterm start --workspace "$ws_name" --cwd "$dir"
    elif [ -n "''${WEZTERM_PANE:-}" ]; then
      # Inside WezTerm — check if workspace already exists
      existing_pane=$(${wezterm}/bin/wezterm cli list --format json \
        | ${pkgs.jq}/bin/jq -r --arg ws "$ws_name" \
            '.[] | select(.workspace == $ws) | .pane_id' \
        | head -n1)
      if [ -n "$existing_pane" ]; then
        # Switch to existing workspace by activating one of its panes
        ${wezterm}/bin/wezterm cli activate-pane --pane-id "$existing_pane"
      else
        ${wezterm}/bin/wezterm cli spawn --workspace "$ws_name" --cwd "$dir" >/dev/null
      fi
    else
      # Outside WezTerm but mux is running — spawn in target workspace
      ${wezterm}/bin/wezterm cli spawn --workspace "$ws_name" --cwd "$dir" >/dev/null
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
