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

    # Open workspaces are the source of truth for "is a workspace already open for
    # this directory". Pull them (real names + cwd) from the running mux so we can
    # switch to an existing workspace by its ACTUAL name and only create when none is
    # open. This is what makes create-first / switch-after reliable even for
    # auto-named workspaces (whose name != the directory basename).
    json=$(${wezterm}/bin/wezterm cli list --format json 2>/dev/null || printf '[]')
    # "<workspace>\t<cwd>" per pane; cwd stripped of the file://<host> prefix and any
    # trailing slash so it compares cleanly with zoxide paths.
    ws_dirs=$(printf '%s' "$json" | ${pkgs.jq}/bin/jq -r \
      '.[] | [.workspace, (.cwd | sub("^file://[^/]*"; "") | sub("/+$"; ""))] | @tsv' 2>/dev/null || true)
    current=$(printf '%s' "$json" | ${pkgs.jq}/bin/jq -r --arg p "''${WEZTERM_PANE:-}" \
      'first(.[] | select((.pane_id | tostring) == $p) | .workspace) // ""' 2>/dev/null || true)

    # 1. Resolve the target directory.
    mru_file="$HOME/.cache/wezterm-workspace-mru"
    if [ $# -gt 0 ]; then
      dir=$(${pkgs.zoxide}/bin/zoxide query "$@") || exit 1
    else
      # Picker: recently-used (MRU cache) + open-workspace dirs + everything zoxide
      # knows — normalized, deduped, current workspace excluded. Each row is DISPLAYED
      # as the workspace name when one is already open for that dir, otherwise the full
      # path; the real directory is carried in a hidden 2nd column (tab-separated) that
      # the selection logic below reads, so presentation is decoupled from behaviour.
      mru_dirs=""
      [ -r "$mru_file" ] && mru_dirs=$(${pkgs.coreutils}/bin/cut -f2 "$mru_file")
      open_dirs=$(printf '%s\n' "$ws_dirs" | ${pkgs.coreutils}/bin/cut -f2)
      CUR_DIRS=$(printf '%s\n' "$ws_dirs" | ${pkgs.gawk}/bin/awk -F'\t' -v c="$current" '$1 == c { print $2 }')
      export CUR_DIRS
      sel=$(${pkgs.gawk}/bin/awk -F'\t' '
          BEGIN { n = split(ENVIRON["CUR_DIRS"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") excl[a[i]] = 1 }
          NR == FNR { if ($2 != "") name[$2] = $1; next }
          { d = $0; sub(/\/+$/, "", d); if (d == "" || (d in excl) || seen[d]++) next; print ((d in name) ? name[d] : d) "\t" d }
        ' <(printf '%s\n' "$ws_dirs") <( {
            printf '%s\n' "$mru_dirs"
            printf '%s\n' "$open_dirs"
            ${pkgs.zoxide}/bin/zoxide query -l 2>/dev/null || true
          } ) \
        | ${pkgs.fzf}/bin/fzf --delimiter='\t' --with-nth=1 --reverse --preview 'ls -1 --color=always {2}') || exit 0
      dir=$(printf '%s' "$sel" | ${pkgs.coreutils}/bin/cut -f2)
    fi
    dir=''${dir%/}
    [ -n "$dir" ] || exit 0

    # 2. Switch to the workspace already open for this directory, else create one.
    #    A workspace matches when it belongs to the SAME git repo (same toplevel) as
    #    the chosen dir — compared by git root, so a parent dir like $HOME can't
    #    over-match an unrelated child repo, and a pane sitting in a subdir still maps
    #    back to its repo's workspace.
    git_root=$(${pkgs.git}/bin/git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
    root="''${git_root:-$dir}"
    ws=$(printf '%s\n' "$ws_dirs" | while IFS=$'\t' read -r wname wcwd; do
        [ -n "$wcwd" ] || continue
        wroot=$(${pkgs.git}/bin/git -C "$wcwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$wcwd")
        if [ "$wroot" = "$root" ]; then printf '%s\n' "$wname"; break; fi
      done)
    if [ -n "$ws" ]; then
      ws_name="$ws"
      target_cwd=""        # existing workspace → switch only (no spawn)
    else
      ws_name="''${root##*/}"
      target_cwd="$root"   # new workspace → create at the repo root
    fi
    [ -n "$ws_name" ] || exit 0

    # 3. Switch to (or create) the workspace.
    #
    # WezTerm's CLI cannot change the active workspace — only the GUI can, via the
    # SwitchToWorkspace action. So hand the request to the GUI through a user var
    # (OSC 1337 SetUserVar named "switch-workspace", value = base64 of
    # "<name>\t<cwd>"). The wezterm.lua `user-var-changed` handler performs the
    # actual switch. This works when `t` is run inside a WezTerm pane.
    if [ -n "''${WEZTERM_PANE:-}" ]; then
      payload=$(printf '%s\t%s' "$ws_name" "$target_cwd" | ${pkgs.coreutils}/bin/base64 | tr -d '\n')
      osc=$(printf '\033]1337;SetUserVar=switch-workspace=%s\a' "$payload")
      esc=$(printf '\033')
      if [ -n "''${TMUX:-}" ]; then
        # Inside tmux: wrap for passthrough (needs `set -g allow-passthrough on`),
        # doubling every ESC in the inner sequence.
        printf '\033Ptmux;%s\033\\' "''${osc//$esc/$esc$esc}" > /dev/tty
      else
        printf '%s' "$osc" > /dev/tty
      fi
      # Keep this (possibly transient) pane alive briefly so WezTerm reads and
      # processes the OSC before the process exits — otherwise a throwaway pane like
      # the tab LEADER T spawns is torn down before the switch is handled.
      ${pkgs.coreutils}/bin/sleep 0.3
    elif ${wezterm}/bin/wezterm cli list >/dev/null 2>&1; then
      # A mux is running but we're not inside a WezTerm pane — best effort: create
      # the workspace in a new window (focus may not follow; use CTRL+t T to switch).
      ${wezterm}/bin/wezterm cli spawn --new-window --workspace "$ws_name" --cwd "''${target_cwd:-$dir}" >/dev/null
    else
      # No running instance — start one in the target workspace.
      ${wezterm}/bin/wezterm start --workspace "$ws_name" --cwd "''${target_cwd:-$dir}"
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
