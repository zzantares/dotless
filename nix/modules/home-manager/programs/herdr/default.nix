{
  config,
  lib,
  pkgs,
  ...
}:

let
  # `t` for herdr: pick an open workspace or a zoxide directory, same one-list
  # flow as prefix+T in tmux and wezterm. Bound to prefix+shift+T below.
  herdr-t = pkgs.writeShellApplication {
    name = "herdr-t";
    runtimeInputs = [
      pkgs.herdr
      pkgs.fzf
      pkgs.jq
      pkgs.zoxide
      pkgs.git
    ];
    text = ''
      open=$(
        jq -rn --slurpfile w <(herdr workspace list) --slurpfile p <(herdr pane list) '
          ($p[0].result.panes | group_by(.workspace_id)
            | map({ key: .[0].workspace_id, value: .[0].cwd }) | from_entries) as $cwd
          | $w[0].result.workspaces[]
          | [ "W", .workspace_id, "● " + .label, ($cwd[.workspace_id] // "") ]
          | @tsv'
      )

      # A directory already open is offered once, as its workspace.
      opened=$(printf '%s\n' "$open" | cut -f4 | grep -v '^$' || true)
      dirs=$(zoxide query -l |
        if [ -n "$opened" ]; then grep -vxF "$opened" || true; else cat; fi |
        awk -v OFS='\t' '{ print "D", $0, "  " $0, "" }')

      selected=$(
        printf '%s\n%s\n' "$open" "$dirs" | grep -v '^$' |
          fzf --ansi --reverse --no-sort --delimiter='\t' --with-nth=3,4 \
            --prompt='herdr> ' --header='workspaces and directories'
      )
      [ -n "$selected" ] || exit 0

      target=$(printf '%s' "$selected" | cut -f2)
      if [ "$(printf '%s' "$selected" | cut -f1)" = "W" ]; then
        herdr workspace focus "$target" >/dev/null
      else
        # T_SESSION_USE_GIT_ROOT: a path inside a repo opens the repo, like `t`.
        root=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$target")
        herdr workspace create --cwd "$root" --focus >/dev/null
      fi
    '';
  };
in
{
  # Brings the `dotless.appearance` options this module sets.
  imports = [ ./../../appearance ];

  home.packages = [ herdr-t ];

  programs.herdr = {
    enable = lib.mkDefault true;

    # herdr writes this file itself (in-app settings, `herdr channel set`), so
    # merge instead of linking a read-only store path. Declared keys still win
    # on every activation.
    mutableSettings = lib.mkDefault true;

    settings = {
      onboarding = false;

      theme.name = "catppuccin";

      terminal = {
        default_shell = "${config.programs.zsh.package}/bin/zsh";
        # Splits and tabs inherit the focused pane's directory, as tmux does
        # with `-c "#{pane_current_path}"`.
        new_cwd = "follow";
      };

      # Nix owns the version; `herdr update` cannot write the store.
      update.version_check = false;

      session.resume_agents_on_restore = true;

      ui = {
        # tmux's window list sits under the panes, not over them.
        tab_bar_position = "bottom";
        # `bind c new-window` asks for nothing.
        prompt_new_tab_name = false;
        # tmux draws splitters between panes only.
        pane_outer_borders = false;
        # pane-active-border-style fg from tmux.conf.
        accent = "#a4b9ef";
        toast.delivery = "herdr";
      };

      # Keys follow tmux and wezterm (config/wezterm/wezterm.lua), including
      # Colemak-DH directions: h=up, k=down, j=left, l=right.
      keys = {
        # C-b, plus C-t as tmux's prefix2. Terminals that own C-t (wezterm,
        # ghostty) shadow it; passthrough ones deliver it here.
        prefix = [
          "ctrl+b"
          "ctrl+t"
        ];

        # Splits: v beside, s below, with the tmux punctuation as aliases.
        split_vertical = [
          "prefix+v"
          "prefix+%"
        ];
        split_horizontal = [
          "prefix+s"
          "prefix+double_quote"
          "prefix+minus"
        ];

        focus_pane_up = [
          "prefix+h"
          "prefix+up"
        ];
        focus_pane_left = [
          "prefix+j"
          "prefix+left"
        ];
        focus_pane_down = [
          "prefix+k"
          "prefix+down"
        ];
        focus_pane_right = [
          "prefix+l"
          "prefix+right"
        ];

        # tmux binds resize to prefix+HKJL directly. prefix+r still opens
        # herdr's resize mode, but that mode's own hjkl are vim-fixed.
        resize_pane_up = "prefix+shift+h";
        resize_pane_left = "prefix+shift+j";
        resize_pane_down = "prefix+shift+k";
        resize_pane_right = "prefix+shift+l";
        resize_mode = "prefix+r";

        # tmux's swap-pane -U / -D.
        swap_pane_up = "prefix+{";
        swap_pane_down = "prefix+}";

        # last-window / last-pane, which tmux gives three keys.
        last_pane = [
          "prefix+t"
          "prefix+b"
        ];

        zoom = "prefix+z";
        close_pane = "prefix+x";
        copy_mode = "prefix+[";
        rename_pane = "prefix+shift+p";

        new_tab = "prefix+c";
        next_tab = "prefix+n";
        previous_tab = "prefix+p";
        switch_tab = "prefix+1..9";
        rename_tab = "prefix+comma";
        close_tab = [
          "prefix+shift+x"
          "prefix+&"
        ];

        # prefix+Space is tmux's `choose-tree -s`.
        workspace_picker = [
          "prefix+w"
          "prefix+space"
        ];
        # prefix+o is tmux's Claude session picker.
        goto = [
          "prefix+g"
          "prefix+o"
        ];
        new_workspace = "prefix+shift+n";
        rename_workspace = [
          "prefix+shift+w"
          "prefix+$"
        ];
        close_workspace = "prefix+shift+d";
        previous_workspace = "prefix+(";
        next_workspace = "prefix+)";
        # prefix+O is tmux's picker with attention markers.
        open_notification_target = "prefix+shift+o";

        detach = [
          "prefix+q"
          "prefix+d"
        ];
        help = "prefix+?";
        settings = "prefix+shift+s";
        reload_config = "prefix+shift+r";
        # prefix+b is last-window here, so the sidebar moves up a key.
        toggle_sidebar = "prefix+shift+b";

        # Navigate mode takes plain keys: the copy-mode and choose-tree
        # remappings from tmux.conf.
        navigate_workspace_up = "h";
        navigate_workspace_down = "k";
        navigate_pane_left = "j";
        navigate_pane_right = "l";
        navigate_pane_up = "shift+h";
        navigate_pane_down = "shift+k";

        command = [
          {
            key = "prefix+shift+t";
            type = "popup";
            command = lib.getExe herdr-t;
            description = "workspaces and zoxide directories";
            width = "80%";
            height = "60%";
          }
        ];
      };
    };
  };

  dotless.appearance.path = [ pkgs.jaq ];

  # `mutableSettings` makes config.toml a real file rather than a link, so the
  # theme can be rewritten in place. herdr writes this file too, hence the
  # read-modify-write through a temporary.
  dotless.appearance.hooks.herdr = ''
    if [ "$mode" = light ]; then
      theme=solarized-light
    else
      theme=catppuccin
    fi

    settings=${lib.escapeShellArg "${config.xdg.configHome}/herdr/config.toml"}
    [ -f "$settings" ] || exit 0

    tmp=$(mktemp "$settings.XXXXXX")
    jaq --from toml --to toml ".theme.name = \"$theme\"" "$settings" >"$tmp"
    mv "$tmp" "$settings"
  '';
}
