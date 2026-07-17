{
  profile,
  config,
  lib,
  pkgs,
  ...
}:

let
  # Convention: if the consumer places config/hypr/local.conf in their flake root,
  # symlink it out-of-store (live-editable, auto-reloads on change, no rebuild needed).
  # Otherwise create an empty placeholder so the `source` directive doesn't error.
  # Evaluated at switch time under --impure.
  userDir = "${config.home.homeDirectory}/${profile.flakeRoot}/config/hypr";
  hasUserConfig = builtins.pathExists "${userDir}/local.conf";

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
  imports = [ ./waybar.nix ];

  # pinentry-qt works on Wayland without a full DE, unlike pinentry-gnome3.
  services.gpg-agent.pinentry.package = pkgs.pinentry-qt;

  wayland.windowManager.hyprland = {
    enable = lib.mkDefault true;
    # TODO: migrate extraConfig (submap section) to Lua and switch to "lua"
    configType = "hyprlang";

    settings = {
      input = {
        follow_mouse = 1;
        kb_layout = "us";
        kb_variant = "colemak";
        kb_options = "ctrl:nocaps";
        touchpad = {
          natural_scroll = true;
          disable_while_typing = true;
        };
      };

      cursor = {
        no_hardware_cursors = true;
      };

      "exec-once" = [
        # Propagate compositor env to systemd user session (needed for portals, services).
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland"
        # Polkit authentication agent (required for privilege escalation dialogs).
        "${pkgs.hyprpolkitagent}/lib/hyprpolkitagent"
        # NetworkManager tray applet — right-click to manage WiFi connections.
        "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator"
      ];

      general = {
        gaps_in = 10;
        gaps_out = 10;
        border_size = 2;
        layout = "dwindle";
      };

      decoration = {
        rounding = 10;
      };

      animations = {
        enabled = true;
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
      };

      bind =
        [
          # ── Essentials ──
          "SUPER, Return, exec, wezterm"
          "SUPER CTRL, t, exec, alacritty"
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
          "SUPER, slash, layoutmsg, togglesplit" # tiles horizontal ↔ vertical
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

          # ── Media / hardware keys ──
          # Brightness: backlight device names vary per machine; add to local.conf:
          #   bindel = , XF86MonBrightnessUp, exec, swayosd-client --brightness raise --device <dev>
          #   bindel = , XF86MonBrightnessDown, exec, swayosd-client --brightness lower --device <dev>
          ", XF86AudioRaiseVolume, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume raise; ${pkgs.pipewire}/bin/pw-play ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/audio-volume-change.oga"
          ", XF86AudioLowerVolume, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume lower; ${pkgs.pipewire}/bin/pw-play ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/audio-volume-change.oga"
          ", XF86AudioMute, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume mute-toggle; ${pkgs.pipewire}/bin/pw-play ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/audio-volume-change.oga"

          # ── Service submap (physical ; → Colemak O) ──
          "SUPER SHIFT, o, submap, service"
        ]
        ++ mkWorkspaceBinds
        ++ mkMoveToWorkspaceBinds;

      # ── Window auto-placement ──
      # Hyprland 0.55: match properties use "match:prop regex" syntax.
      windowrule = [
        "workspace name:E, match:class (emacs|Emacs)"
        "workspace name:T, match:class (org\\.wezfurlong\\.wezterm)"
        "workspace name:F, match:class (firefox|Firefox)"
      ];
    };

    # Service submap (modal keybindings, like AeroSpace's service mode).
    # Keys are mnemonic (f = float) using Colemak characters.
    extraConfig = ''
      submap = service
      bind = , escape, submap, reset
      bind = , f, exec, hyprctl --batch "dispatch togglefloating ; dispatch submap reset"
      bind = , r, exec, hyprctl reload && hyprctl dispatch submap reset && notify-send -u low -t 2000 "Hyprland" "Config reloaded"
      bind = , l, exec, hyprlock
      submap = reset

      # Per-consumer overrides — sourced last so they can override anything above.
      # Create config/hypr/local.conf in your flake root to customise without rebuilding.
      source = ${config.home.homeDirectory}/.config/hypr/local.conf
    '';
  };

  services.hyprpaper = {
    enable = true;
    settings = {
      preload = [ "${profile.wallpaper}" ];
      wallpaper = [ ", ${profile.wallpaper}" ];
    };
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        disable_loading_bar = true;
        hide_cursor = true;
      };
      background = [
        {
          monitor = "";
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
          brightness = 0.5;
        }
      ];
      "input-field" = [
        {
          monitor = "";
          size = "300, 50";
          outline_thickness = 2;
          outer_color = "rgb(8ba4b0)";
          inner_color = "rgb(282727)";
          font_color = "rgb(c5c9c5)";
          fade_on_empty = true;
          placeholder_text = "<i>Password</i>";
          check_color = "rgb(87a987)";
          fail_color = "rgb(c4746e)";
          fail_text = "<i>$FAIL</i>";
        }
      ];
      label = [
        {
          monitor = "";
          text = "$TIME";
          color = "rgba(c5c9c5ff)";
          font_size = 64;
          font_family = "Overpass";
          halign = "center";
          valign = "center";
          position = "0, 200";
        }
        {
          monitor = "";
          text = "$DATE";
          color = "rgba(a09e9cff)";
          font_size = 18;
          font_family = "Overpass";
          halign = "center";
          valign = "center";
          position = "0, 130";
        }
      ];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        after_sleep_cmd = "hyprctl dispatch dpms on";
        ignore_dbus_inhibit = false;
        lock_cmd = "hyprlock";
      };
      listener = [
        {
          # Dim screen after 5 minutes of inactivity.
          timeout = 300;
          "on-timeout" = "${pkgs.brightnessctl}/bin/brightnessctl -s set 10%";
          "on-resume" = "${pkgs.brightnessctl}/bin/brightnessctl -r";
        }
        {
          # Lock screen after 10 minutes.
          timeout = 600;
          "on-timeout" = "hyprlock";
        }
        {
          # Suspend after 15 minutes — only when on battery (never on AC).
          timeout = 900;
          "on-timeout" = "grep -ql 1 /sys/class/power_supply/*/online || systemctl suspend";
        }
      ];
    };
  };

  services.mako = {
    enable = true;
    settings = {
      font = "Overpass 12";
      "background-color" = "#1d1c19ee";
      "text-color" = "#c5c9c5";
      "border-color" = "#8ba4b0";
      "border-radius" = 8;
      "border-size" = 2;
      "default-timeout" = 5000;
      padding = "12";
      width = 320;
      height = 100;
      "max-icon-size" = 32;
      layer = "overlay";
    };
  };

  # swayosd-server as a systemd user service so it starts with the session
  # and restarts on crash — more robust than exec-once.
  systemd.user.services.swayosd-server = {
    Unit = {
      Description = "SwayOSD server";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.swayosd}/bin/swayosd-server";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Consumer override: live symlink when provided, empty placeholder otherwise.
  xdg.configFile."hypr/local.conf" =
    if hasUserConfig
    then { source = config.lib.file.mkOutOfStoreSymlink "${userDir}/local.conf"; }
    else { text = ""; };

  home.packages = with pkgs; [
    wl-clipboard
    wofi
    pavucontrol
    brightnessctl
    hyprpolkitagent
    networkmanagerapplet
    libnotify
    swayosd
  ];
}
