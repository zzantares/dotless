;;; parts/frames.el -*- lexical-binding: t; -*-

;; `fullscreen' frame parameter both hooks apply. Set it from a later layer to
;; change how frames open - macOS wants `maximized', since native fullscreen
;; moves the frame to its own Space.
(defvar zz/frame-fullscreen 'fullboth
  "Value for the `fullscreen' frame parameter applied to new frames.")

;; When connecting via emacsclient, start the frame fullscreen and fix theme cursor colors.
;; We use `set-frame-parameter' instead of `toggle-frame-fullscreen' to avoid toggling —
;; tools like Magit's with-editor can trigger this hook a second time (for their own
;; internal frames), and a toggle would exit fullscreen on the existing frame.
;; Avoid `(add-to-list 'default-frame-alist '(fullscreen . fullboth))' as that triggers
;; a theme cursor color bug. See: https://github.com/doomemacs/doomemacs/issues/6221
(add-hook! 'server-after-make-frame-hook
  (when (display-graphic-p)
    (set-frame-parameter nil 'fullscreen zz/frame-fullscreen))
  (consult-theme doom-theme)
  (global-disable-mouse-mode 1)
  (mapc #'disable-mouse-in-keymap
        (list evil-insert-state-map)))

;; This hooks only runs on startup, it won't run when connecting via emacsclient that's fine here
;; `set-frame-parameter' rather than `toggle-frame-fullscreen' so the same
;; variable decides, and a re-run cannot toggle fullscreen back off.
(add-hook! 'window-setup-hook :append
           #'(lambda ()
               (when (display-graphic-p)
                 (set-frame-parameter nil 'fullscreen zz/frame-fullscreen))
               (global-disable-mouse-mode 1)
               (mapc #'disable-mouse-in-keymap
                     (list evil-insert-state-map))))
