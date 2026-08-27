-- Emacs Client launcher.
--
-- Forwards files and org-protocol:// URLs to the running Emacs daemon, then
-- raises the Emacs GUI. Built as an AppleScript applet because only an Apple
-- Event-handling app can receive Finder "Open With", drag-and-drop, and
-- URL-scheme events.
--
-- @emacsclient@ is substituted with its store path at build time.

-- Ensure the Emacs daemon is up, then wait for its server socket to accept
-- connections, before any emacsclient call that does real work.
--
-- We start the daemon via launchctl rather than `emacsclient -a ''`. The `-a ''`
-- form would have emacsclient fork its own daemon when none is running, but that
-- daemon would be an unmanaged child of this app and miss the launchd job's
-- ProcessType=Interactive scheduling tier. Kickstarting the launchd job instead
-- guarantees the only daemon that ever exists is the Interactive one — so we
-- deliberately omit `-a ''` from every emacsclient call below.
on ensureDaemon()
  try
    do shell script "/bin/launchctl kickstart gui/$(id -u)/org.nix-community.home.emacs"
  end try
  -- kickstart returns before the server socket is ready on a cold start, so
  -- poll briefly (~5s) rather than racing the first emacsclient call.
  try
    do shell script "for i in $(seq 1 25); do @emacsclient@ -e t >/dev/null 2>&1 && exit 0; sleep 0.2; done"
  end try
end ensureDaemon

on focusEmacs()
  -- Bring the Emacs GUI process frontmost FIRST. emacsclient's
  -- select-frame-set-input-focus raises the frame within Emacs and asks AppKit
  -- to self-activate, but on recent macOS a background process can't reliably
  -- activate itself (focus-steal suppression) — the window surfaces but the app
  -- never becomes active, forcing a CMD+TAB. The applet, as the process Spotlight
  -- actually launched, is allowed to direct activation, so we hand it over via an
  -- explicit Apple Event before picking the frame to focus.
  try
    tell application id "org.gnu.Emacs" to activate
  end try
  try
    do shell script "@emacsclient@ -e '(select-frame-set-input-focus (car (visible-frame-list)))'"
  end try
end focusEmacs

-- Files opened via "Open With" or dropped on the app icon.
on open theDropped
  ensureDaemon()
  repeat with oneDrop in theDropped
    set dropPath to quoted form of POSIX path of oneDrop
    try
      do shell script "@emacsclient@ --reuse-frame -n " & dropPath
    end try
  end repeat
  focusEmacs()
end open

-- Plain launch from Spotlight, Dock, or Finder (no file).
on run
  ensureDaemon()
  try
    do shell script "@emacsclient@ --reuse-frame -n"
  end try
  focusEmacs()
end run

-- org-protocol:// URLs (org-capture, org-roam, etc.).
on open location this_URL
  ensureDaemon()
  try
    do shell script "@emacsclient@ -n " & quoted form of this_URL
  end try
  focusEmacs()
end open location
