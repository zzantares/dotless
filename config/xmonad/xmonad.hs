module Main where

import Data.List (find)
import Data.Map qualified as Map
import Graphics.X11.ExtraTypes.XF86
import XMonad
import XMonad.Actions.CycleWS (nextWS, prevWS)
import XMonad.StackSet qualified as W
import XMonad.Config.Desktop (desktopConfig)
import XMonad.Hooks.DynamicLog (PP (..), wrap, xmobarColor, xmobarPP)
import XMonad.Hooks.InsertPosition (Focus (..), Position (..), insertPosition)
import XMonad.Hooks.StatusBar (statusBarProp, withSB)
import XMonad.Layout.PerWorkspace (onWorkspace)
import XMonad.Layout.ThreeColumns (ThreeCol (ThreeColMid))
import XMonad.Util.EZConfig (additionalKeys)

-- Named workspaces with Nerd Font icons (mod+1 through mod+9 still work by index).
myWorkspaces :: [String]
myWorkspaces =
    [ "\xf120 var" -- terminal
    , "\xf121 dev" -- code
    , "\xf269 www" -- browser
    , "\xf025 mus" -- headphones
    , "\xf03d vid" -- video
    , "\xf03e img" -- image
    , "\xf11b gmr" -- gamepad
    , "\xf0c0 soc" -- users
    , "\xf013 sys" -- cog
    ]

{- | Catppuccin Mocha palette for xmobar workspace indicators.
Active workspace is highlighted in lavender; empty ones are dimmed.
-}
myXmobarPP :: PP
myXmobarPP =
    xmobarPP
        { ppCurrent = xmobarColor "#cba6f7" "" . wrap " " " "
        , ppHidden = xmobarColor "#cdd6f4" "" . wrap " " " "
        , ppHiddenNoWindows = xmobarColor "#45475a" "" . wrap " " " "
        , ppUrgent = xmobarColor "#f38ba8" "" . wrap "!" "!"
        , ppSep = ""
        , ppTitle = const "" -- window title hidden; workspaces are enough
        , ppLayout = const "" -- layout indicator hidden
        }

-- | Launches three Firefox windows for the www dashboard workspace.
-- Each window gets a distinct WM class so manage hooks can place them correctly.
-- Delays ensure windows open in the right order: browser first (centre master),
-- then calendar (right slave), then todoist (left slave).
dashboardCmd :: String
dashboardCmd =
    "firefox & sleep 2; firefox --new-window https://todoist.com & sleep 2; firefox --new-window https://calendar.google.com &"

-- | Dashboard layout: three vertical columns at 25% / 50% / 25%.
-- ThreeColMid puts the master in the centre; slaves fill right then left.
-- Stack order → column:  [0] centre  [1] right  [2] left
myLayout = onWorkspace "\xf269 www" dashLayout (layoutHook desktopConfig)
  where
    dashLayout = ThreeColMid 1 (3 / 100) (1 / 2)

-- | Shift a window to a workspace and switch to it.
viewShift :: WorkspaceId -> ManageHook
viewShift ws = doShift ws <+> doF (W.greedyView ws)

-- | Define window rules, what apps start where.
myManageHook :: ManageHook
myManageHook =
    composeAll
        [ className =? "Albert" --> doFloat
        -- Firefox dashboard: open order matters: browser (centre) → todoist (right) → calendar (left).
        -- All windows share the same WM class; inserting at End preserves open order in the stack.
        , className =? "firefox" --> insertPosition End Newer <+> viewShift "\xf269 www"
        ]

-- | Move the focused window to the www workspace and place it in the centre (master).
sendToWwwCenter :: X ()
sendToWwwCenter = do
    ss <- gets windowset
    let www    = "\xf269 www"
        fromWs = W.currentTag ss
    case W.peek ss of
        Nothing -> return ()
        Just newCenter -> windows $ \s ->
            let mOldMaster = do
                    ws  <- find ((== www) . W.tag) (W.workspaces s)
                    stk <- W.stack ws
                    let m = head (W.integrate stk)
                    if m /= newCenter then Just m else Nothing
                -- Move newCenter to www
                s1 = W.shiftWin www newCenter s
                -- Make newCenter the master on www without switching screens
                s2 = W.mapWorkspace (\ws ->
                    if W.tag ws /= www then ws
                    else ws { W.stack = fmap (makeMaster newCenter) (W.stack ws) }
                    ) s1
                -- Send old master back to the originating workspace
                s3 = case mOldMaster of
                    Just old -> W.shiftWin fromWs old s2
                    Nothing  -> s2
            in s3
  where
    makeMaster w stk =
        let ws = w : filter (/= w) (W.integrate stk)
        in W.Stack (head ws) [] (tail ws)

main :: IO ()
main =
    xmonad . withSB (statusBarProp "xmobar-launch" (pure myXmobarPP)) $
        desktopConfig
            { -- The modifier key `mod4Mask` is the Super/Windows key.
              modMask = mod4Mask
            , terminal = "alacritty"
            , borderWidth = 1
            , workspaces = myWorkspaces
            , layoutHook = myLayout
            , manageHook = myManageHook <+> manageHook desktopConfig
            , startupHook = spawn "notify-send 'XMonad' 'Restarted'"
            , normalBorderColor = "#45475a"
            , focusedBorderColor = "#cba6f7"
            }
            `additionalKeys` [
                               -- App launcher: Alt+Space toggles Albert (starts it if not running)
                               ((mod1Mask, xK_space), spawn "albert toggle")
                             , -- Volume control (scripts also send a dunst OSD notification with a progress bar)
                               ((0, xF86XK_AudioRaiseVolume), spawn "xmonad-volume-up")
                             , ((0, xF86XK_AudioLowerVolume), spawn "xmonad-volume-down")
                             , ((0, xF86XK_AudioMute), spawn "xmonad-volume-mute")
                             , -- Brightness control (requires user to be in the 'video' group)
                               ((0, xF86XK_MonBrightnessUp), spawn "xmonad-brightness-up")
                             , ((0, xF86XK_MonBrightnessDown), spawn "xmonad-brightness-down")
                             , -- Workspace cycling (also triggered by 3-finger touchpad swipe via libinput-gestures)
                               ((mod4Mask, xK_Right), nextWS)
                             , ((mod4Mask, xK_Left), prevWS)
                             , -- Screenshots
                               ((0, xK_Print), spawn "maim -s | tee ~/Pictures/Screenshots/screenshot-$(date +%F-%T).png | xclip -selection clipboard -t image/png && notify-send 'Screenshot copied'")
                             , ((shiftMask, xK_Print), spawn "maim | tee ~/Pictures/Screenshots/screenshot-$(date +%F-%T).png | xclip -selection clipboard -t image/png && notify-send 'Screenshot copied'")
                             , -- Open Alacritty
                               ((mod4Mask .|. controlMask, xK_t), spawn "alacritty")
                             , -- Open Emacs
                               ((mod4Mask .|. controlMask, xK_e), spawn "emacsclient -c -n")
                             , -- Open LibreWolf
                               ((mod4Mask .|. controlMask, xK_l), spawn "librewolf")
                             , -- Open Firefox
                               ((mod4Mask .|. controlMask, xK_f), spawn "firefox")
                             , -- Launch the www dashboard: browser (centre) + calendar (right) + todoist (left)
                               ((mod4Mask .|. controlMask, xK_w), spawn dashboardCmd)
                             , -- Send focused window to the www workspace and place it in the centre
                               ((mod4Mask .|. shiftMask, xK_Return), sendToWwwCenter)
                             ]

help :: String
help =
    unlines
        [ "The default modifier key is 'alt'. Default keybindings:"
        , ""
        , "-- launching and killing programs"
        , "mod-Shift-Enter  Launch xterminal"
        , "mod-p            Launch albert"
        , "mod-Shift-p      Launch gmrun"
        , "mod-Shift-c      Close/kill the focused window"
        , "mod-Space        Rotate through the available layout algorithms"
        , "mod-Shift-Space  Reset the layouts on the current workSpace to default"
        , "mod-n            Resize/refresh viewed windows to the correct size"
        , ""
        , "-- move focus up or down the window stack"
        , "mod-Tab        Move focus to the next window"
        , "mod-Shift-Tab  Move focus to the previous window"
        , "mod-j          Move focus to the next window"
        , "mod-k          Move focus to the previous window"
        , "mod-m          Move focus to the master window"
        , ""
        , "-- modifying the window order"
        , "mod-Return   Swap the focused window and the master window"
        , "mod-Shift-j  Swap the focused window with the next window"
        , "mod-Shift-k  Swap the focused window with the previous window"
        , ""
        , "-- resizing the master/slave ratio"
        , "mod-h  Shrink the master area"
        , "mod-l  Expand the master area"
        , ""
        , "-- floating layer support"
        , "mod-t  Push window back into tiling; unfloat and re-tile it"
        , ""
        , "-- increase or decrease number of windows in the master area"
        , "mod-comma  (mod-,)   Increment the number of windows in the master area"
        , "mod-period (mod-.)   Deincrement the number of windows in the master area"
        , ""
        , "-- quit, or restart"
        , "mod-Shift-q  Quit xmonad"
        , "mod-q        Restart xmonad"
        , "mod-[1..9]   Switch to workSpace N"
        , ""
        , "-- Workspaces & screens"
        , "mod-Shift-[1..9]   Move client to workspace N"
        , "mod-{w,e,r}        Switch to physical/Xinerama screens 1, 2, or 3"
        , "mod-Shift-{w,e,r}  Move client to screen 1, 2, or 3"
        , ""
        , "-- Mouse bindings: default actions bound to mouse events"
        , "mod-button1  Set the window to floating mode and move by dragging"
        , "mod-button2  Raise the window to the top of the stack"
        , "mod-button3  Set the window to floating mode and resize by dragging"
        ]
