;;; parts/frames.el -*- lexical-binding: t; -*-

;; When connecting via emacsclient, start the frame fullscreen and fix theme cursor colors.
;; We use `set-frame-parameter' instead of `toggle-frame-fullscreen' to avoid toggling —
;; tools like Magit's with-editor can trigger this hook a second time (for their own
;; internal frames), and a toggle would exit fullscreen on the existing frame.
;; Avoid `(add-to-list 'default-frame-alist '(fullscreen . fullboth))' as that triggers
;; a theme cursor color bug. See: https://github.com/doomemacs/doomemacs/issues/6221
(add-hook! 'server-after-make-frame-hook
  (when (display-graphic-p)
    (set-frame-parameter nil 'fullscreen 'fullboth))
  (consult-theme doom-theme)
  (global-disable-mouse-mode 1)
  (mapc #'disable-mouse-in-keymap
        (list evil-insert-state-map)))

;; This hooks only runs on startup, it won't run when connecting via emacsclient that's fine here
(add-hook! 'window-setup-hook :append
           #'(lambda ()
               (when (display-graphic-p)
                 (toggle-frame-fullscreen))
               (global-disable-mouse-mode 1)
               (mapc #'disable-mouse-in-keymap
                     (list evil-insert-state-map))))
