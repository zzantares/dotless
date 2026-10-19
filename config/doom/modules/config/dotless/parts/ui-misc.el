;;; parts/ui-misc.el -*- lexical-binding: t; -*-

(after! button
  (map! :map button-map :nv "o" #'push-button))

(after! doom-themes
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t))

(after! doom-modeline
  (setq doom-modeline-icon t)
  (setq doom-modeline-persp-name t))
