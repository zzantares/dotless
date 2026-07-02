{
  lib,
  pkgs,
  ...
}:

let
  # Direction mapping (standard HJKL):
  #   h = up, j = left, k = down, l = right
  navKeys = [
    "h"
    "j"
    "k"
    "l"
  ];

  # Letter workspaces: all lowercase letters excluding navigation keys.
  # Workspace name matches the Colemak keysym — press the key you see, go to
  # the workspace with that letter.
  workspaceLetters = lib.filter (l: !(builtins.elem l navKeys)) (
    lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz"
  );

  mkWorkspaceBinds = map (l: "SUPER, ${l}, workspace, name:${lib.toUpper l}") workspaceLetters;

  mkMoveToWorkspaceBinds = map (
    l: "SUPER SHIFT, ${l}, movetoworkspace, name:${lib.toUpper l}"
  ) workspaceLetters;
in
{
  wayland.windowManager.hyprland = {
    enable = lib.mkDefault true;

    settings = {
      input = {
        follow_mouse = 1;
        touchpad = {
          natural_scroll = true;
          tap_to_click = true;
          disable_while_typing = true;
        };
      };

      general = {
        gaps_in = 10;
        gaps_out = 10;
        border_size = 2;
        layout = "dwindle";
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      decoration = {
        rounding = 10;
      };

      animations = {
        enabled = true;
      };

      bind =
        [
          # ── Essentials ──
          "SUPER, Return, exec, alacritty"
          "SUPER SHIFT, backspace, killactive"
          "SUPER, space, exec, wofi --show drun"

          # ── Focus (HJKL) ──
          "SUPER, h, movefocus, u"
          "SUPER, j, movefocus, l"
          "SUPER, k, movefocus, d"
          "SUPER, l, movefocus, r"

          # ── Move window ──
          "SUPER SHIFT, h, movewindow, u"
          "SUPER SHIFT, j, movewindow, l"
          "SUPER SHIFT, k, movewindow, d"
          "SUPER SHIFT, l, movewindow, r"

          # ── Layout ──
          "SUPER, slash, togglesplit" # tiles horizontal ↔ vertical
          "SUPER, comma, togglegroup" # closest to AeroSpace accordion

          # ── Resize ──
          "SUPER, minus, resizeactive, -50 -50"
          "SUPER, equal, resizeactive, 50 50"

          # ── Numbered workspaces ──
          "SUPER, 1, workspace, 1"
          "SUPER, 2, workspace, 2"
          "SUPER, 3, workspace, 3"
          "SUPER, 4, workspace, 4"
          "SUPER, 5, workspace, 5"
          "SUPER, 6, workspace, 6"
          "SUPER, 7, workspace, 7"
          "SUPER, 8, workspace, 8"
          "SUPER, 9, workspace, 9"

          "SUPER SHIFT, 1, movetoworkspace, 1"
          "SUPER SHIFT, 2, movetoworkspace, 2"
          "SUPER SHIFT, 3, movetoworkspace, 3"
          "SUPER SHIFT, 4, movetoworkspace, 4"
          "SUPER SHIFT, 5, movetoworkspace, 5"
          "SUPER SHIFT, 6, movetoworkspace, 6"
          "SUPER SHIFT, 7, movetoworkspace, 7"
          "SUPER SHIFT, 8, movetoworkspace, 8"
          "SUPER SHIFT, 9, movetoworkspace, 9"

          # ── Workspace navigation ──
          "SUPER, tab, workspace, previous" # back-and-forth
          "SUPER SHIFT, tab, movecurrentworkspacetomonitor, +1"

          # ── Service submap (physical ; → Colemak O) ──
          "SUPER SHIFT, o, submap, service"
        ]
        ++ mkWorkspaceBinds
        ++ mkMoveToWorkspaceBinds;

      # ── Window auto-placement ──
      windowrulev2 = [
        "workspace name:E, class:^(emacs|Emacs)$"
        "workspace name:T, class:^(org\\.wezfurlong\\.wezterm)$"
        "workspace name:F, class:^(firefox|Firefox)$"
      ];
    };

    # Service submap (modal keybindings, like AeroSpace's service mode).
    # Keys are mnemonic (f = float) using Colemak characters.
    extraConfig = ''
      submap = service
      bind = , escape, submap, reset
      bind = , f, exec, hyprctl --batch "dispatch togglefloating ; dispatch submap reset"
      bind = , r, exec, hyprctl reload
      submap = reset
    '';
  };

  home.packages = with pkgs; [
    wl-clipboard
    wofi
  ];
}
