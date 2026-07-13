{ pkgs, ... }:

# Kanagawa Dragon palette:
#   bg       #181616    bg+1  #1d1c19    surface  #282727
#   fg       #c5c9c5    muted #a09e9c
#   red      #c4746e    green #87a987    teal     #8ea4a2
#   blue     #8ba4b0    gold  #c4b28a    iris     #a292a3

{
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 36;
        spacing = 4;

        "modules-left" = [ "hyprland/workspaces" "hyprland/submap" ];
        "modules-center" = [ "clock" ];
        "modules-right" = [
          "network"
          "pulseaudio"
          "cpu"
          "memory"
          "battery"
          "tray"
        ];

        "hyprland/submap" = {
          format = " {}";
          max-length = 10;
          tooltip = false;
        };

        "hyprland/workspaces" = {
          format = "{name}";
          on-click = "activate";
          sort-by-name = true;
        };

        clock = {
          format = " {:%H:%M}";
          "format-alt" = " {:%A, %d %b}";
          "tooltip-format" = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
        };

        cpu = {
          format = " {usage}%";
          tooltip = false;
          interval = 2;
        };

        memory = {
          format = " {percentage}%";
          "tooltip-format" = "{used:0.1f}G / {total:0.1f}G";
        };

        network = {
          "format-wifi" = "󰤨 {signalStrength}%";
          "format-ethernet" = "󰈀 {ipaddr}";
          "format-disconnected" = "󰤭";
          "tooltip-format-wifi" = "{essid} ({signalStrength}%)\n{ifname}";
          "tooltip-format-ethernet" = "{ifname}: {ipaddr}";
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          "format-muted" = "󰝟";
          "format-icons" = {
            default = [ "󰕿" "󰖀" "󰕾" ];
          };
          "on-click" = "${pkgs.pavucontrol}/bin/pavucontrol";
          "scroll-step" = 5;
        };

        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          "format-charging" = "󰂄 {capacity}%";
          "format-plugged" = "󰚥 {capacity}%";
          "format-icons" = [ "󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
          "tooltip-format" = "{timeTo}\nDraw: {power}W";
        };

        tray = {
          "icon-size" = 18;
          spacing = 8;
        };
      };
    };

    style = ''
      * {
        font-family: "Overpass Nerd Font", "Overpass";
        font-size: 13px;
        border: none;
        border-radius: 0;
        min-height: 0;
      }

      window#waybar {
        background-color: #181616;
        color: #c5c9c5;
        border-bottom: 2px solid #282727;
      }

      .modules-left  { padding: 0 4px; }
      .modules-right { padding: 0 4px; }

      /* ── Workspaces ── */
      #workspaces button {
        padding: 0 8px;
        background: transparent;
        color: #a09e9c;
        border-radius: 4px;
        margin: 4px 2px;
        transition: all 0.15s ease;
      }

      #workspaces button:hover {
        background: #282727;
        color: #c5c9c5;
      }

      #workspaces button.active {
        background: #282727;
        color: #8ba4b0;
        border-bottom: 2px solid #8ba4b0;
      }

      #workspaces button.urgent {
        color: #c4746e;
        border-bottom: 2px solid #c4746e;
      }

      /* ── Submap ── */
      #submap {
        color: #c4b28a;
        background: #282727;
        border-radius: 4px;
        padding: 0 8px;
        margin: 4px 2px;
        font-weight: bold;
      }

      /* ── Center ── */
      #clock {
        color: #c5c9c5;
        font-weight: bold;
        padding: 0 8px;
      }

      /* ── Right modules ── */
      #cpu     { color: #87a987; padding: 0 6px; }
      #memory  { color: #8ea4a2; padding: 0 6px; }
      #network { color: #8ba4b0; padding: 0 6px; }
      #network.disconnected { color: #c4746e; }
      #pulseaudio { color: #a292a3; padding: 0 6px; }
      #pulseaudio.muted { color: #625e5a; }
      #battery { color: #c4b28a; padding: 0 6px; }
      #battery.charging, #battery.plugged { color: #87a987; }
      #battery.warning:not(.charging)  { color: #c4b28a; }
      #battery.critical:not(.charging) { color: #c4746e; }
      #tray { padding: 0 6px; }

      /* ── Tooltips ── */
      tooltip {
        background-color: #1d1c19;
        border: 1px solid #393836;
        border-radius: 8px;
      }

      tooltip label { color: #c5c9c5; }
    '';
  };
}
