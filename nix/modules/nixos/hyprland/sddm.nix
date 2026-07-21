{ pkgs, profile, ... }:

let
  # SDDM 0.21 renamed the greeter binary to sddm-greeter-qt6 but
  # findGreeterTheme() still validates against the old "sddm-greeter" name,
  # causing theme validation to fail and falling back to a black screen.
  # Add a sddm-greeter → sddm-greeter-qt6 symlink so the check passes.
  # kdePackages.sddm is a runCommand derivation ("sddm-wrapped"), not a stdenv
  # build — it has buildCommand, not postInstall. Override buildCommand to append
  # a sddm-greeter → sddm-greeter-qt6 symlink after the existing setup.
  sddmWithGreeterAlias = pkgs.kdePackages.sddm.overrideAttrs (old: {
    buildCommand = old.buildCommand + ''
      ln -sf $out/bin/sddm-greeter-qt6 $out/bin/sddm-greeter
    '';
  });

  # Sugar Dark SDDM theme patched for Qt6 compatibility, with custom
  # wallpaper, frosted-glass panel, and hardened password input.
  sddmTheme = pkgs.stdenvNoCC.mkDerivation {
    name = "sugar-dark-zephyrus";
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/share/sddm/themes
      cp -r ${pkgs.sddm-sugar-dark}/share/sddm/themes/sugar-dark \
            $out/share/sddm/themes/sugar-dark
      chmod -R u+w $out/share/sddm/themes/sugar-dark
      cp ${profile.wallpaper} \
         $out/share/sddm/themes/sugar-dark/Background.jpg
      # Theme colours: frost white on the nebula palette.
      # PartialBlur makes the login panel semi-transparent (frosted-glass).
      sed -i \
        -e 's/^MainColor=.*/MainColor="#e8eef8"/' \
        -e 's/^AccentColor=.*/AccentColor="white"/' \
        $out/share/sddm/themes/sugar-dark/theme.conf
      echo "PartialBlur=true" >> $out/share/sddm/themes/sugar-dark/theme.conf
      # Sugar Dark imports QtGraphicalEffects (Qt5 name). In Qt6 this module is
      # exposed as Qt5Compat.GraphicalEffects — patch all QML files in place.
      find $out/share/sddm/themes/sugar-dark -name "*.qml" \
        -exec sed -i 's/import QtGraphicalEffects/import Qt5Compat.GraphicalEffects/g' {} \;
      # Blur the background image at runtime using FastBlur from
      # Qt5Compat.GraphicalEffects (already imported in Main.qml).
      # Adjust the radius value to control blur strength.
      awk '
        /mipmap: true/ {
          print
          print "            layer.enabled: true"
          print "            layer.effect: FastBlur { radius: 64 }"
          next
        }
        { print }
      ' $out/share/sddm/themes/sugar-dark/Main.qml > /tmp/main_patched.qml
      mv /tmp/main_patched.qml $out/share/sddm/themes/sugar-dark/Main.qml
      # Set passwordMaskDelay to 0 so each character is immediately replaced
      # by the bullet (•) with no brief flash of the actual character.
      # Add flat: true to the usernameIcon Button so it has no background
      # rectangle — Qt6's Basic style renders Button with a visible dark
      # background by default, which was not the case in Qt5.
      # Suppress the ComboBox default contentItem text (partial username
      # leaking to the left of the icon).
      awk '
        /passwordMaskDelay:/ {
          sub(/passwordMaskDelay:.*/, "passwordMaskDelay: 0")
          print; next
        }
        /textRole: "name"/ {
          print
          print "            contentItem: Item {}"
          next
        }
        /enabled: false/ {
          print
          print "                    flat: true"
          next
        }
        { print }
      ' $out/share/sddm/themes/sugar-dark/Components/Input.qml \
        > /tmp/input_patched.qml
      mv /tmp/input_patched.qml \
         $out/share/sddm/themes/sugar-dark/Components/Input.qml
    '';
  };
in

{
  # Run SDDM on X11 (not Wayland) to avoid PRIME GPU-selection issues with the
  # greeter compositor. Hyprland still starts on Wayland after login — the DM
  # and desktop session are independent processes.
  services.displayManager.sddm.package = sddmWithGreeterAlias;
  # Sugar Dark uses QtGraphicalEffects (Qt5). In Qt6/SDDM 0.21 this module
  # lives in qt5compat — adding it here makes the import resolve correctly.
  services.displayManager.sddm.extraPackages = [ pkgs.qt6.qt5compat ];

  services.xserver.enable = true;
  services.displayManager.sddm.wayland.enable = false;
  # The NVIDIA module sets videoDrivers = mkDefault [ "nvidia" ], which makes X
  # try to initialize PRIME offload and fails with "modeset(0): Failed to create
  # pixmap" on the NVIDIA GPU. For the greeter we only need the AMD iGPU; NVIDIA
  # on-demand offload is DRM/KMS-based and unaffected by this override.
  # Use the generic modesetting driver (kernel KMS/DRM) rather than amdgpu or
  # nvidia. amdgpu fails with "No devices detected" on this GPU (1002:150e,
  # not in its PCI ID table), and nvidia fails with modeset pixmap errors in
  # PRIME offload mode. modesetting works with any DRM device and will use the
  # AMD iGPU which has the display outputs.
  services.xserver.videoDrivers = [ "modesetting" ];
  services.displayManager.sddm.theme = "sugar-dark";

  # Exclude hyprland-uwsm.desktop from SDDM's session list. The uwsm session
  # uses a non-blocking Exec (uwsm start -e) which causes SDDM to close the
  # PAM session before Hyprland starts. Only expose hyprland.desktop (blocking).
  services.displayManager.sddm.settings.Wayland.SessionDir =
    let
      filteredSessions = pkgs.runCommand "wayland-sessions-no-uwsm" { } ''
        mkdir -p $out
        for f in ${pkgs.hyprland}/share/wayland-sessions/*.desktop; do
          name=$(basename "$f")
          case "$name" in
            *uwsm*) ;;
            *) cp "$f" "$out/$name" ;;
          esac
        done
      '';
    in
    "${filteredSessions}";

  environment.systemPackages = [ sddmTheme ];

  # ---- Why QML patches require disabling the Qt disk cache ----------------
  #
  # SDDM reads theme.conf directly in C++ on every start, so changes to that
  # file are always picked up immediately.  QML files (.qml) are different:
  # Qt6 compiles them to bytecode on first use and caches the result under
  # /var/lib/sddm/.cache/ (the sddm user's XDG cache dir).  On subsequent
  # starts Qt validates the cache by comparing the source file's mtime against
  # the mtime stored in the cache entry.  If they match, the cached bytecode
  # is used and the source file is never re-read.
  #
  # The problem: every file in the Nix store has a fixed mtime of epoch 0
  # (1970-01-01 00:00:00 UTC).  No matter how many times the theme derivation
  # is rebuilt with different patches, every new Input.qml and Main.qml always
  # has mtime = 0.  Qt sees mtime(source) == mtime(cache) and silently reuses
  # the stale bytecode — making ALL QML patches no-ops.
  #
  # This was the root cause of a long debugging session where changes to
  # echoMode, passwordCharacter, color, and other QML properties had zero
  # visible effect even though:
  #   - journalctl confirmed SDDM was loading the correct file path
  #   - grep confirmed the patched properties were present in the source file
  #   - theme.conf changes (C++-read) worked fine as a control experiment
  #
  # The fix has two parts:
  #   1. QML_DISABLE_DISK_CACHE=1 on the display-manager service makes Qt
  #      parse QML from source on every SDDM start — no cache reads or writes.
  #   2. The activation script removes any stale cache that was already built
  #      before this env var was introduced.
  #
  # The fix has two parts working together:
  #   1. The activation script removes /var/lib/sddm/.cache on every `just
  #      switch`.  This ensures Qt always recompiles QML from the freshly
  #      patched source on the next boot, regardless of what was cached before.
  #   2. Qt's disk cache is LEFT ENABLED (QML_DISABLE_DISK_CACHE is NOT set).
  #      After the activation script clears the old cache, Qt compiles the
  #      patched QML on the first SDDM start and writes a new cache entry.
  #      Every subsequent boot until the next switch uses that cache, so
  #      startup cost is paid only once per generation.
  #
  # Gotcha: do NOT remove the activation script thinking the cache is harmless.
  # Without it, stale bytecode (mtime=0) survives across switches and QML
  # patches silently stop working.  The activation script is the only thing
  # that breaks the cycle — Qt will not invalidate the cache on its own.
  # -------------------------------------------------------------------------
  system.activationScripts.sddm-clear-qml-cache = ''
    rm -rf /var/lib/sddm/.cache
  '';
}
