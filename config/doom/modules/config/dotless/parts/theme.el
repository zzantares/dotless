;;; parts/theme.el -*- lexical-binding: t; -*-

;; TODO This should be configurable per profile like have a map or smth
(defvar dotless/dark-theme 'nordic-night)
(defvar dotless/light-theme 'doom-solarized-light)

;; A cons is Doom's (DARK . LIGHT): at startup it reads the desktop's
;; color-scheme off the XDG portal and picks. Only at startup - its
;; `enable-theme' hook then overwrites this with the theme it loaded.
(setopt doom-theme (cons dotless/dark-theme dotless/light-theme))

(defun dotless/apply-appearance (mode)
  "Load the theme for MODE, either \"light\" or \"dark\".
Called over emacsclient by `appearance-switch'."
  (interactive (list (completing-read "Mode: " '("light" "dark"))))
  (let ((theme (if (equal mode "light") dotless/light-theme dotless/dark-theme)))
    (unless (custom-theme-enabled-p theme)
      ;; Only ours: `custom-enabled-themes' also holds the face customizations
      ;; Doom re-enables rather than reloads.
      (mapc #'disable-theme
            (seq-intersection custom-enabled-themes
                              (list dotless/dark-theme dotless/light-theme)))
      (load-theme theme t))))
