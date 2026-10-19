;;; parts/so-long.el -*- lexical-binding: t; -*-

(after! so-long
  (map! :map so-long-mode-map
        :nv "h" #'evil-previous-visual-line
        :nv "k" #'evil-next-visual-line
        :nv "j" #'evil-backward-char
        :nv "l" #'evil-forward-char))
