;;; parts/emmet.el -*- lexical-binding: t; -*-

(add-hook! emmet-mode
  (map! :map emmet-mode-keymap :prefix "C-e" :desc "Emmet expand" :i "," #'emmet-expand-line))
