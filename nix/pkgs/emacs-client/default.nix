{
  lib,
  runCommandLocal,
  emacs,
}:

# A macOS app bundle that forwards files and org-protocol:// URLs to the running
# Emacs daemon (kickstarting the launchd job when none is up) instead of spawning
# a second Emacs. An AppleScript applet, not a shell script: only an Apple Event
# handling app receives Finder "Open With", drag-and-drop and URL-scheme events.
#
# IMPURE: shells out to the host's /usr/bin/osacompile and PlistBuddy, so it
# builds on macOS only, with a relaxed sandbox (`__noChroot`, the darwin default).

runCommandLocal "emacs-client-app"
  {
    __noChroot = true;
    meta = {
      description = "macOS launcher that forwards files and org-protocol URLs to the Emacs daemon";
      platforms = lib.platforms.darwin;
    };
  }
  ''
    app="$out/Applications/EmacsClient.app"
    plist="$app/Contents/Info.plist"

    mkdir -p "$out/Applications"

    substitute ${./emacs-client.applescript} emacs-client.applescript \
      --subst-var-by emacsclient '${emacs}/bin/emacsclient'

    /usr/bin/osacompile -o "$app" emacs-client.applescript

    # Set a scalar plist key, replacing whatever osacompile generated.
    setstr() {
      /usr/libexec/PlistBuddy -c "Set :$1 $2" "$plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$plist"
    }

    setstr CFBundleIdentifier         io.gutier.emacsclient
    setstr CFBundleName               "Emacs Client"
    setstr CFBundleDisplayName        "Emacs Client"
    setstr CFBundleVersion            "${lib.getVersion emacs}"
    setstr CFBundleShortVersionString "${lib.getVersion emacs}"
    setstr LSApplicationCategoryType  public.app-category.productivity

    # Register as an editor for common text types so "Open With" / drag-and-drop
    # offer Emacs Client and it can be set as the default handler.
    pb() { /usr/libexec/PlistBuddy -c "$1" "$plist"; }
    pb "Delete :CFBundleDocumentTypes" 2>/dev/null || true
    pb "Add :CFBundleDocumentTypes array"
    pb "Add :CFBundleDocumentTypes:0 dict"
    pb "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Editor"
    pb "Add :CFBundleDocumentTypes:0:CFBundleTypeName string 'Text Document'"
    pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes array"
    pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string public.text"
    pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes:1 string public.plain-text"
    pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes:2 string public.source-code"
    pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes:3 string public.script"
    pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes:4 string public.shell-script"
    pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes:5 string public.data"

    # Register the org-protocol:// URL scheme (org-capture, org-roam, ...).
    pb "Delete :CFBundleURLTypes" 2>/dev/null || true
    pb "Add :CFBundleURLTypes array"
    pb "Add :CFBundleURLTypes:0 dict"
    pb "Add :CFBundleURLTypes:0:CFBundleURLName string 'Org Protocol'"
    pb "Add :CFBundleURLTypes:0:CFBundleURLSchemes array"
    pb "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string org-protocol"

    # Replace osacompile's default droplet icon with the Emacs icon.
    cp ${emacs}/Applications/Emacs.app/Contents/Resources/Emacs.icns \
      "$app/Contents/Resources/applet.icns"
    setstr CFBundleIconFile applet
  ''
