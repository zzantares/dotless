;;; parts/theme.el -*- lexical-binding: t; -*-

;; TODO This should be configurable per profile like have a map or smth
(defvar dotless/dark-theme 'nordic-night)
(defvar dotless/light-theme 'doom-solarized-light)

(setopt doom-theme dotless/dark-theme)

(defun dotless/apply-appearance (mode)
  "Load the MODE theme, where MODE is \"light\" or \"dark\".
Called over emacsclient by `appearance-switch'."
  (interactive (list (completing-read "Mode: " '("light" "dark"))))
  (let ((theme (if (equal mode "light") dotless/light-theme dotless/dark-theme)))
    (unless (eq theme doom-theme)
      ;; Doom's loader disables the outgoing theme first; a bare `load-theme'
      ;; stacks them and leaves faces from both.
      (setopt doom-theme theme)
      (doom/reload-theme))))
