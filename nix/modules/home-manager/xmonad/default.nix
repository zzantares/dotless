{
  profile,
  config,
  lib,
  pkgs,
  ...
}:

let
  # xremap built with X11 application-detection support (the nixpkgs default only
  # has wlroots; x11rb is pure Rust so no extra C deps are required).
  xremap-x11 = pkgs.xremap.overrideAttrs (_: {
    cargoBuildFeatures = "x11";
    cargoCheckFeatures = "x11";
  });

  # Wrapper scripts that perform the action and send a dunst OSD notification.
  # Dunst displays a progress bar when the `int:value` hint is provided (0-100).
  # The `x-canonical-private-synchronous` hint replaces the previous notification
  # with the same tag so rapid key presses update a single notification in-place.
  notify = "${pkgs.libnotify}/bin/notify-send";
  bctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  volumeSound = "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/audio-volume-change.oga";

  volumeUp = pkgs.writeShellScriptBin "xmonad-volume-up" ''
    pactl set-sink-volume @DEFAULT_SINK@ +5%
    vol=$(pactl get-sink-volume @DEFAULT_SINK@ | awk '/Volume:/{ gsub(/%/,"",$5); print $5; exit }')
    ${notify} -h string:x-canonical-private-synchronous:audio-volume \
      -h int:value:"$vol" -t 1500 "Volume" "$vol%"
    paplay ${volumeSound} &
  '';

  volumeDown = pkgs.writeShellScriptBin "xmonad-volume-down" ''
    pactl set-sink-volume @DEFAULT_SINK@ -5%
    vol=$(pactl get-sink-volume @DEFAULT_SINK@ | awk '/Volume:/{ gsub(/%/,"",$5); print $5; exit }')
    ${notify} -h string:x-canonical-private-synchronous:audio-volume \
      -h int:value:"$vol" -t 1500 "Volume" "$vol%"
    paplay ${volumeSound} &
  '';

  volumeMute = pkgs.writeShellScriptBin "xmonad-volume-mute" ''
    pactl set-sink-mute @DEFAULT_SINK@ toggle
    if pactl get-sink-mute @DEFAULT_SINK@ | grep -q "yes"; then
      ${notify} -h string:x-canonical-private-synchronous:audio-volume \
        -h int:value:0 -t 1500 "Volume" "Muted"
    else
      vol=$(pactl get-sink-volume @DEFAULT_SINK@ | awk '/Volume:/{ gsub(/%/,"",$5); print $5; exit }')
      ${notify} -h string:x-canonical-private-synchronous:audio-volume \
        -h int:value:"$vol" -t 1500 "Volume" "$vol%"
      paplay ${volumeSound} &
    fi
  '';

  brightnessUp = pkgs.writeShellScriptBin "xmonad-brightness-up" ''
    ${bctl} set +10%
    brightness=$(( $(${bctl} get) * 100 / $(${bctl} max) ))
    ${notify} -h string:x-canonical-private-synchronous:brightness \
      -h int:value:"$brightness" -t 1500 "Brightness" "$brightness%"
  '';

  brightnessDown = pkgs.writeShellScriptBin "xmonad-brightness-down" ''
    ${bctl} set 10%-
    brightness=$(( $(${bctl} get) * 100 / $(${bctl} max) ))
    ${notify} -h string:x-canonical-private-synchronous:brightness \
      -h int:value:"$brightness" -t 1500 "Brightness" "$brightness%"
  '';

  # Watches pactl events and switches the default sink between headphones (HDA
  # card) and HDMI when the headphone jack is plugged/unplugged.  The two sinks
  # are identified by stable name substrings rather than hardcoded full names so
  # the script survives minor hardware changes.
  audioSinkSwitch = pkgs.writeShellScriptBin "audio-sink-switch" ''
    HEADPHONE_PATTERN="sofhdadsp__sink"
    HDMI_PATTERN="hdmi"

    headphones_plugged() {
      pactl list cards | awk '/\[Out\] Headphones:/{print}' \
        | grep -v "not available" | grep -q "available"
    }

    find_sink() {
      pactl list sinks short | awk -v pat="$1" '$2 ~ pat {print $2; exit}'
    }

    switch_sink() {
      local sink="$1"
      [ -z "$sink" ] && return 1
      pactl set-default-sink "$sink"
      pactl list sink-inputs short \
        | awk '{print $1}' \
        | xargs -r -I{} pactl move-sink-input {} "$sink"
    }

    # Apply correct sink for the current jack state at startup.
    if headphones_plugged; then
      switch_sink "$(find_sink "$HEADPHONE_PATTERN")"
    fi

    # React to jack plug/unplug events going forward.
    pactl subscribe 2>/dev/null | while IFS= read -r line; do
      if [[ "$line" == *"Event 'change' on card"* ]]; then
        sleep 0.3
        if headphones_plugged; then
          switch_sink "$(find_sink "$HEADPHONE_PATTERN")"
        else
          sink="$(find_sink "$HDMI_PATTERN")"
          [ -z "$sink" ] && sink="$(find_sink "$HEADPHONE_PATTERN")"
          switch_sink "$sink"
        fi
      fi
    done
  '';

  # Periodically checks battery level and sends threshold notifications.
  # Runs via a systemd timer. Uses /tmp sentinel files to fire each alert only once
  # per charge/discharge cycle rather than on every poll.
  batteryAlert = pkgs.writeShellScriptBin "battery-alert" ''
    WARNING_LEVEL=20
    CRITICAL_LEVEL=5

    status=$(${pkgs.acpi}/bin/acpi -b 2>/dev/null | head -1)
    [ -z "$status" ] && exit 0

    level=$(echo "$status" | tr ',' '\n' | grep '%' | tr -dc '0-9')
    state=$(echo "$status" | awk -F'[:,]' '{gsub(/ /,"",$2); print $2}')

    case "$state" in
      Charging|"Notcharging"|Full)
        rm -f /tmp/battery-low /tmp/battery-critical
        if [ "$level" -gt 99 ] && [ ! -f /tmp/battery-full ]; then
          ${notify} "Battery Full" "Battery is fully charged." \
            -u low -i battery-full-charged -t 5000 -r 9991
          touch /tmp/battery-full
        fi
        ;;
      Discharging)
        rm -f /tmp/battery-full
        if [ "$level" -le "$CRITICAL_LEVEL" ] && [ ! -f /tmp/battery-critical ]; then
          ${notify} "Critical Battery" "$level% remaining — plug in now!" \
            -u critical -i battery-caution -t 0 -r 9991
          touch /tmp/battery-critical
          rm -f /tmp/battery-low
        elif [ "$level" -le "$WARNING_LEVEL" ] && [ ! -f /tmp/battery-low ]; then
          ${notify} "Low Battery" "$level% remaining." \
            -u normal -i battery-low -t 10000 -r 9991
          touch /tmp/battery-low
        fi
        ;;
    esac
  '';

  # Watches upower events and notifies on AC plug/unplug.
  # Runs as a long-lived user service tied to the graphical session.
  batteryPowerNotify = pkgs.writeShellScriptBin "battery-power-notify" ''
    ${pkgs.upower}/bin/upower --monitor | while IFS= read -r line; do
      if echo "$line" | grep -qi "line_power"; then
        sleep 1
        bat=$(${pkgs.upower}/bin/upower -e 2>/dev/null | grep -i "BAT" | head -1)
        [ -z "$bat" ] && continue
        info=$(${pkgs.upower}/bin/upower -i "$bat" 2>/dev/null)
        state=$(echo "$info" | awk '/[[:space:]]state:/{print $2}')
        level=$(echo "$info" | awk '/percentage:/{gsub(/%/,"",$2); print $2}')
        case "$state" in
          charging)
            ${notify} "Battery" "Charging: $level%" \
              -u low -i battery-good-charging -t 5000 -r 9992
            ;;
          discharging)
            ${notify} "Battery" "Unplugged: $level% remaining." \
              -u low -i battery-good -t 5000 -r 9992
            ;;
        esac
      fi
    done
  '';

  # Launches xmobar with the config matching the active autorandr profile.
  # Used by XMonad's statusBarProp so the right config is always loaded on restart.
  # Requests a session lock via the standard logind D-Bus interface.
  # xss-lock (started in xprofile) listens for this signal and invokes
  # xscreensaver-command -lock. All lock sources (Albert, keybindings, lid
  # close, idle timeout) flow through the same path this way.
  lockScreen = pkgs.writeShellScriptBin "xmonad-lock" ''
    exec loginctl lock-session
  '';

  # Retries autorandr --change up to 5 times with 1s gaps so the EDID is ready
  # after a hotplug udev event fires before the kernel has finished reading it.
  autorandrBin = "${pkgs.autorandr}/bin/autorandr";
  xmobarBin = "${pkgs.haskellPackages.xmobar.bin}/bin/xmobar";
  xsettingsdBin = "${pkgs.xsettingsd}/bin/xsettingsd";

  autorandrChange = pkgs.writeShellScriptBin "autorandr-change" ''
    for i in 1 2 3 4 5; do
      ${autorandrBin} --change && exit 0
      sleep 1
    done
    exit 1
  '';

  xmobarLaunch = pkgs.writeShellScriptBin "xmobar-launch" ''
    if ${autorandrBin} --detected | grep -q "^external$"; then
      exec ${xmobarBin} "$HOME/.config/xmobar/xmobarrc-external"
    else
      exec ${xmobarBin} "$HOME/.config/xmobar/xmobarrc"
    fi
  '';

  # Launches xsettingsd with the config matching the active autorandr profile.
  # Used by the xsettingsd systemd service so the correct DPI is applied at
  # session start and automatically picks up profile switches via a service restart.
  xsettingsdLaunch = pkgs.writeShellScriptBin "xsettingsd-launch" ''
    if ${autorandrBin} --detected | grep -q "^external$"; then
      exec ${xsettingsdBin} --config "$HOME/.config/xsettingsd/xsettingsd-external.conf"
    else
      exec ${xsettingsdBin} --config "$HOME/.config/xsettingsd/xsettingsd.conf"
    fi
  '';
in
{
  xsession.enable = lib.mkDefault true;

  # GDM on Ubuntu auto-sources ~/.xprofile for ALL X sessions (including GNOME).
  # The default profilePath generates ~/.xprofile which would run
  # `systemctl --user stop graphical-session.target` — killing GNOME's session.
  # By using a non-standard path, GDM ignores it; ~/.xsession sources it explicitly.
  xsession.profilePath = ".xprofile-hm";

  programs.autorandr = {
    enable = lib.mkDefault true;

    profiles = {
      # Laptop display only (no external monitor connected)
      laptop = {
        fingerprint = {
          eDP-1 = "00ffffffffffff0009e5e00a000000002c1f0104b5221578037ce5a4554c9f260f5054000000010101010101010101010101010101016b6e00a0a04084603020360058d71000001a000000fd0c3ca51f1f4e010a202020202020000000fe00424f452043510a202020202020000000fe004e4531363051444d2d4e59310a01807013790000030114a52f0185ff099f002f001f003f0683000200050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003e90";
        };
        hooks.postswitch = ''
          systemctl --user restart xsettingsd
          echo "Xft.dpi: 120" | xrdb -merge
          alacritty msg config font.size=12 font.offset.y=6 2>/dev/null || true
          pkill -x xmobar || true
          sleep 0.3
          xmobar-launch &
        '';
        config = {
          eDP-1 = {
            enable = true;
            primary = true;
            mode = "2560x1600";
            rate = "165.00";
            position = "0x0";
          };
        };
      };

      # External monitor connected: laptop on the left, external on the right (primary)
      external = {
        fingerprint = {
          eDP-1 = "00ffffffffffff0009e5e00a000000002c1f0104b5221578037ce5a4554c9f260f5054000000010101010101010101010101010101016b6e00a0a04084603020360058d71000001a000000fd0c3ca51f1f4e010a202020202020000000fe00424f452043510a202020202020000000fe004e4531363051444d2d4e59310a01807013790000030114a52f0185ff099f002f001f003f0683000200050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003e90";
          HDMI-1-0 = "00ffffffffffff000469a527010101010f190103803c2278ea4455a9554d9d260f5054bfef80714f81808100b30081409500a940d1c0565e00a0a0a0295030203500555021000012000000fd00384b1e5318000a202020202020000000fc004d58323741510a202020202020000000ff0046344c4d52533030333338380a017502031df14a900403011412051f0713230907078301000065030c003000023a801871382d40582c450055502100001e565e00a0a0a029503020350055502100001e011d007251d01e206e28550055502100001ed60980a020e02d10086022005550210808180000000000000000000000000000000000000000000000000000c6";
        };
        hooks.postswitch = ''
          systemctl --user restart xsettingsd
          echo "Xft.dpi: 96" | xrdb -merge
          alacritty msg config font.size=11 font.offset.y=4 2>/dev/null || true
          ${notify} -t 5000 "External display" "Restart Firefox to apply correct font size"
          pkill -x xmobar || true
          sleep 0.3
          xmobar-launch &
        '';
        config = {
          eDP-1 = {
            enable = true;
            primary = false;
            mode = "2560x1600";
            rate = "165.00";
            position = "0x0";
          };
          HDMI-1-0 = {
            enable = true;
            primary = true;
            mode = "2560x1440";
            rate = "59.95";
            position = "2560x0";
          };
        };
      };
    };
  };

  services.autorandr.enable = lib.mkDefault true;

  # XMonad sessions don't benefit from GNOME keyring's SSH agent (that's only
  # started automatically for GNOME sessions), so run HM's ssh-agent instead.
  # SSH keys are added on first use via addKeysToAgent = "yes" in ssh config.
  services.ssh-agent.enable = true;

  systemd.user.services.autorandr.Service.ExecStart =
    pkgs.lib.mkForce "${autorandrChange}/bin/autorandr-change";

  # Adjusts color temperature by time of day (warm at night, neutral during the day).
  # Runs as a systemd user service tied to graphical-session.target — XMonad only.
  # GNOME has its own Night Light; this service is not active there.
  services.redshift = {
    enable = lib.mkDefault true;
    latitude = "19.4326";
    longitude = "-99.1332";
    temperature = {
      day = 6500;
      night = 3500;
    };
    brightness = {
      day = "1.0";
      night = "0.8";
    };
  };

  home.packages = with pkgs; [
    albert
    xremap-x11 # Per-app key remapper (e.g. Ctrl+W → word delete in Albert)
    acpi # Battery status (used by battery-alert)
    brightnessctl # Backlight control
    dunst # Notification daemon
    feh # Wallpaper setter
    libinput-gestures # 3-finger touchpad gesture daemon (requires 'input' group)
    libnotify # notify-send for OSD notifications
    nerd-fonts.hack # Nerd Font for xmobar workspace icons
    maim # Utility for screenshot
    haskellPackages.xmobar.bin # Status bar (config written to xmobar/xmobarrc)
    picom # Compositor (transparency, vsync)
    polkit_gnome # Authentication agent for privilege dialogs
    upower # Power management D-Bus service CLI (used by battery-power-notify)
    xdotool # Simulate key presses for libinput-gestures
    volumeUp
    volumeDown
    volumeMute
    brightnessUp
    brightnessDown
    autorandrChange
    batteryAlert
    batteryPowerNotify
    xmobarLaunch
    xsettingsdLaunch
    xsettingsd
    audioSinkSwitch
    lockScreen
  ];

  # Session file for display managers that support user-local sessions (LightDM, SDDM).
  # GDM on Ubuntu reads only /usr/share/xsessions/ — run once after activating this config:
  #   sudo cp ~/.local/share/xsessions/xmonad.desktop /usr/share/xsessions/
  xdg.dataFile."xsessions/xmonad.desktop".text = ''
    [Desktop Entry]
    Name=XMonad
    Comment=Lightweight X11 tiling window manager written in Haskell
    Exec=${config.home.homeDirectory}/.xsession
    Type=Application
  '';

  # Extra profile setup sourced only by ~/.xsession (not by GDM for GNOME).
  xsession.profileExtra = ''
    # Prefer GNOME keyring's SSH agent socket; it may already exist at this
    # point (PAM starts gnome-keyring-daemon at login). Fall back to the
    # systemd-activated socket only if the keyring socket is absent.
    _ks="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/keyring/ssh"
    if [ -S "$_ks" ]; then
      export SSH_AUTH_SOCK="$_ks"
    elif [ -z "$SSH_AUTH_SOCK" ]; then
      export SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent"
    fi
    unset _ks
  '';

  # Remap Ctrl+W → Ctrl+BackSpace only when Albert is focused.
  # Qt's QLineEdit uses Ctrl+BackSpace for word deletion; Ctrl+W is not bound by default.
  xdg.configFile."xremap/config.yaml".text = ''
    keymap:
      - name: albert
        application:
          only: albert
        remap:
          C-w: C-BackSpace
  '';

  # Runs inside ~/.xsession only (not sourced by GNOME), before the WM starts.
  xsession.initExtra = ''
    # Signal dark mode preference to GTK apps and Firefox (prefers-color-scheme)
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

    # Apply the saved autorandr profile matching the currently connected displays
    autorandr --change

    # Set wallpaper
    ${pkgs.feh}/bin/feh --bg-fill ${profile.wallpaper} &

    # xscreensaver daemon — must be running for xscreensaver-command -lock to work.
    # apt-installed so Ubuntu's PAM stack handles authentication (Nix's PAM
    # hardcodes /run/wrappers/bin/unix_chkpwd which doesn't exist on Ubuntu).
    /usr/bin/xscreensaver -nosplash &

    # xss-lock bridges logind lock signals to the actual screen locker.
    # Any lock request (loginctl lock-session, lid close, idle) invokes xscreensaver.
    ${pkgs.xss-lock}/bin/xss-lock -- /usr/bin/xscreensaver-command -lock &

    # Compositor: prevents screen tearing and enables transparency
    ${pkgs.picom}/bin/picom --daemon &

    # Notification daemon
    ${pkgs.dunst}/bin/dunst &

    # Polkit authentication agent for privilege escalation dialogs
    ${pkgs.polkit_gnome}/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

    # App launcher — delayed slightly so XMonad is managing windows before Albert
    # starts. Without this, any startup dialog Albert shows (e.g. after an unclean
    # shutdown) is unmanaged and may block Albert from finishing its initialisation.
    (sleep 3 && ${pkgs.albert}/bin/albert) &

    # Key remapper: Ctrl+W → Ctrl+BackSpace in Albert (requires 'input' group, same as libinput-gestures)
    ${xremap-x11}/bin/xremap --watch ${config.xdg.configHome}/xremap/config.yaml &

    # 3-finger swipe gesture daemon (requires user to be in the 'input' group)
    ${pkgs.libinput-gestures}/bin/libinput-gestures &

    # Touchpad settings (equivalent to GNOME's natural-scroll and tap-to-click).
    # Finds all libinput touchpad devices at runtime and applies settings.
    ${pkgs.xinput}/bin/xinput list | grep -i touchpad | \
      sed 's/.*id=\([0-9]*\).*/\1/' | \
      while read -r id; do
        ${pkgs.xinput}/bin/xinput set-prop "$id" "libinput Natural Scrolling Enabled" 1 2>/dev/null || true
        ${pkgs.xinput}/bin/xinput set-prop "$id" "libinput Tapping Enabled" 1 2>/dev/null || true
      done

    # Mouse natural scroll: match pointer devices that are not the touchpad or
    # virtual/test devices.
    ${pkgs.xinput}/bin/xinput list | grep -i pointer | grep -iv "touchpad\|virtual\|xtest" | \
      sed 's/.*id=\([0-9]*\).*/\1/' | \
      while read -r id; do
        ${pkgs.xinput}/bin/xinput set-prop "$id" "libinput Natural Scrolling Enabled" 1 2>/dev/null || true
      done
  '';

  # libinput-gestures config: map 3-finger swipes to Super+Left/Right for workspace cycling.
  # Swipe left (fingers move left) = go to next workspace; swipe right = previous.
  xdg.configFile."libinput-gestures.conf".text = ''
    gesture swipe left  3 xdotool key super+Right
    gesture swipe right 3 xdotool key super+Left
  '';

  # Keyboard layout for XMonad session. In GNOME, gnome-settings-daemon handles
  # this via dconf; in XMonad, home-manager creates a setxkbmap.service unit that
  # runs when hm-graphical-session.target starts.
  home.keyboard = {
    layout = "us";
    variant = "colemak";
    options = [ "ctrl:nocaps" ];
  };

  # DPI for Xft-based apps (xmobar, xterm, etc.). This applies to all X sessions,
  # not just XMonad — but that's fine: GNOME apps use XSETTINGS (set by
  # gnome-settings-daemon to 96 × text-scaling-factor = 120) and ignore this,
  # while legacy Xft apps benefit from having the correct value in both sessions.
  xresources.properties."Xft.dpi" = 120;

  # programs.xmobar writes to ~/.config/xmobar/.xmobarrc (leading dot), but xmobar
  # only searches for ~/.config/xmobar/xmobarrc (no dot) or ~/.xmobarrc.
  # Write directly to the correct path and install the package manually.
  xdg.configFile."xmobar/xmobarrc".text = ''
    Config
      -- xmobar 0.45+ uses a cairo/pango rendering backend. Font strings must
      -- use Pango format ("Family Size"), not the old xft: prefix format.
      -- position = Top auto-sizes by font height but is broken for Pango fonts;
      -- TopSize sets an explicit pixel height instead.
      { font    = "Hack Nerd Font Mono 14"
      , bgColor = "#1e1e2e"
      , fgColor = "#cdd6f4"
      , position = BottomSize C 100 34

      -- Workspace log on the left (piped from XMonad via statusBarProp).
      -- }{  splits left-aligned from right-aligned sections.
      , template = " %XMonadLog%  }{ <fc=#6c7086>cpu</fc> %cpu%  <fc=#6c7086>mem</fc> %memory%  %dynnetwork%  %battery%  %date% "

      , commands =
          [ Run XMonadLog

          -- CPU usage: green → yellow → red as load increases
          , Run Cpu
              [ "--Low"    , "20"  , "--High"  , "60"
              , "--low"    , "#a6e3a1"
              , "--normal" , "#f9e2af"
              , "--high"   , "#f38ba8"
              , "--template", "<total>%"
              ] 10

          -- RAM usage percentage
          , Run Memory
              [ "--template", "<usedratio>%"
              , "--Low"     , "50"
              , "--High"    , "80"
              , "--low"     , "#a6e3a1"
              , "--normal"  , "#f9e2af"
              , "--high"    , "#f38ba8"
              ] 10

          -- Network: auto-selects the most active interface
          , Run DynNetwork
              [ "--template", "<fc=#89b4fa>↓</fc><rx>b/s <fc=#89b4fa>↑</fc><tx>b/s"
              , "--Low"     , "1000"
              , "--High"    , "5000000"
              ] 10

          -- Battery: hides indicator entirely when on AC and full
          , Run Battery
              [ "--template", "<acstatus>"
              , "--Low"     , "20"
              , "--High"    , "80"
              , "--low"     , "#f38ba8"
              , "--normal"  , "#f9e2af"
              , "--high"    , "#a6e3a1"
              , "--"
              , "-o", "<fc=#f9e2af>\xf242</fc> <left>% (<timeleft>)"
              , "-O", "<fc=#a6e3a1>\xf0e7</fc> <left>%"
              , "-i", ""
              ] 50

          -- Date: day name + day number in teal, time in default color
          , Run Date "<fc=#89dceb>%a %d</fc> %H:%M" "date" 10
          ]
      }
  '';

  # XSETTINGS daemon config for the laptop display (120 DPI — matches Xft.dpi).
  # xsettingsd makes GTK3/4 apps respect DPI without needing gnome-settings-daemon.
  xdg.configFile."xsettingsd/xsettingsd.conf".text = ''
    Xft/DPI 122880
    Xft/Antialias 1
    Xft/Hinting 1
    Xft/HintStyle "hintfull"
  '';

  # Scaled-down XSETTINGS config for the external display (96 DPI).
  xdg.configFile."xsettingsd/xsettingsd-external.conf".text = ''
    Xft/DPI 98304
    Xft/Antialias 1
    Xft/Hinting 1
    Xft/HintStyle "hintfull"
  '';

  # Scaled-down xmobar config for the external display (lower pixel density).
  # Font size 10 and bar height 24 instead of 14/34.
  xdg.configFile."xmobar/xmobarrc-external".text = ''
    Config
      { font    = "Hack Nerd Font Mono 10"
      , bgColor = "#1e1e2e"
      , fgColor = "#cdd6f4"
      , position = BottomSize C 100 24

      , template = " %XMonadLog%  }{ <fc=#6c7086>cpu</fc> %cpu%  <fc=#6c7086>mem</fc> %memory%  %dynnetwork%  %battery%  %date% "

      , commands =
          [ Run XMonadLog

          , Run Cpu
              [ "--Low"    , "20"  , "--High"  , "60"
              , "--low"    , "#a6e3a1"
              , "--normal" , "#f9e2af"
              , "--high"   , "#f38ba8"
              , "--template", "<total>%"
              ] 10

          , Run Memory
              [ "--template", "<usedratio>%"
              , "--Low"     , "50"
              , "--High"    , "80"
              , "--low"     , "#a6e3a1"
              , "--normal"  , "#f9e2af"
              , "--high"    , "#f38ba8"
              ] 10

          , Run DynNetwork
              [ "--template", "<fc=#89b4fa>↓</fc><rx>b/s <fc=#89b4fa>↑</fc><tx>b/s"
              , "--Low"     , "1000"
              , "--High"    , "5000000"
              ] 10

          , Run Battery
              [ "--template", "<acstatus>"
              , "--Low"     , "20"
              , "--High"    , "80"
              , "--low"     , "#f38ba8"
              , "--normal"  , "#f9e2af"
              , "--high"    , "#a6e3a1"
              , "--"
              , "-o", "<fc=#f9e2af>\xf242</fc> <left>% (<timeleft>)"
              , "-O", "<fc=#a6e3a1>\xf0e7</fc> <left>%"
              , "-i", ""
              ] 50

          , Run Date "<fc=#89dceb>%a %d</fc> %H:%M" "date" 10
          ]
      }
  '';

  # Watches for headphone jack events and switches the default audio sink.
  # Runs as a user service tied to the graphical session so it starts/stops
  # with XMonad and restarts automatically if pactl subscribe exits.
  systemd.user.services.audio-sink-switch = {
    Unit = {
      Description = "Auto-switch audio sink on headphone jack plug/unplug";
      After = [
        "pipewire.service"
        "pulseaudio.service"
      ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${audioSinkSwitch}/bin/audio-sink-switch";
      Restart = "on-failure";
      RestartSec = "2s";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Polls battery status every 60 seconds and fires threshold notifications.
  systemd.user.services.battery-alert = {
    Unit = {
      Description = "Battery level alert (oneshot check)";
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${batteryAlert}/bin/battery-alert";
    };
  };

  systemd.user.timers.battery-alert = {
    Unit = {
      Description = "Run battery alert check every minute";
      PartOf = [ "graphical-session.target" ];
    };
    Timer = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Watches upower for AC plug/unplug events and notifies the user.
  systemd.user.services.battery-power-notify = {
    Unit = {
      Description = "Battery charging/discharging notifications";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${batteryPowerNotify}/bin/battery-power-notify";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # XSETTINGS daemon: sets GTK DPI based on the active autorandr profile.
  # Running as a proper systemd service (rather than a bare background process
  # launched from autorandr postswitch hooks) ensures:
  #  1. xsettingsd is up before the Emacs daemon starts, so Emacs reads the
  #     correct DPI at frame-creation time rather than falling back to the X11
  #     screen DPI (which reflects the laptop's physical ~216 PPI and makes all
  #     text appear huge on the external display).
  #  2. Profile switches are handled via `systemctl --user restart xsettingsd`
  #     which avoids the pkill/re-exec race condition that could leave the old
  #     (120 DPI laptop) instance running after switching to external.
  systemd.user.services.xsettingsd = {
    Unit = {
      Description = "XSETTINGS daemon for GTK app DPI settings";
      After = [ "graphical-session-pre.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${xsettingsdLaunch}/bin/xsettingsd-launch";
      Restart = "on-failure";
      RestartSec = "0.5s";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Ensure the Emacs daemon starts after xsettingsd so it reads the correct
  # DPI from XSETTINGS rather than falling back to the raw X11 screen DPI.
  systemd.user.services.emacs.Unit = {
    After = pkgs.lib.mkAfter [ "xsettingsd.service" ];
    Wants = [ "xsettingsd.service" ];
  };

  # Symlinked so Albert writes config changes (e.g. new websearch engines) back
  # to the dotfiles repo directly, without requiring a Home Manager rebuild.
  home.file.albert = {
    enable = lib.mkDefault true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${profile.flakeRoot}/config/albert";
    target = "${config.xdg.configHome}/albert";
    force = true; # Replace the backup file if one is already there
  };

  # The xmonad module places the compiled binary here. After `xmonad --recompile`
  # (Super+q), xmonad overwrites HM's symlink with a real file, so on the next
  # `just switch` HM tries to back it up — failing if a backup already exists.
  # force = true makes HM overwrite it directly instead of backing up first.
  home.file.".xmonad/xmonad-x86_64-linux".force = true;

  xsession.windowManager.xmonad = {
    enable = lib.mkDefault true;
    enableContribAndExtras = true;

    # NOTE by setting this to null we're allowed to use `xmonad --recompile` for quick iteration.
    # Once the configuration is stable enough we can set it to the `xmonad.hs` file path to have
    # it be fully declarative, but then `--recompile` won't work as expected.
    config = ./../../../../config/xmonad/xmonad.hs;

    # The haskellPackages used to build xmonad. Uses the overlay-defined package set.
    haskellPackages = pkgs.myHaskellPackages;
  };
}
