;;; parts/nitpick.el -*- lexical-binding: t; -*-

;; `nitpick' ships from dotless; soft-required so this config still loads on a
;; machine whose flake predates it.
(when (require 'nitpick nil t)
  (nitpick-forge-mode 1)
  ;; without it diff-hl marks the wrong lines: see its docstring
  (nitpick-diff-hl-zero-context-mode 1)
  ;; the changed-file pane; a second feature, and nix ships no autoloads
  (when (require 'nitpick-tree nil t)
    ;; `nitpick-tree-mode-map' alone never sees `d': treemacs' evil state
    ;; enables motion state, which suppresses plain letters. An auxiliary map
    ;; on the minor mode is what evil consults first.
    ;; `r' but not `g': `g' is a prefix in motion state, and taking it would
    ;; cost `gg'. Non-evil users get `g' from the mode map itself.
    (after! treemacs-evil
      (evil-define-key 'treemacs nitpick-tree-mode-map
        (kbd "d") #'nitpick-tree-visit-diff
        (kbd "r") #'nitpick-tree-refresh
        (kbd "q") #'nitpick-tree-close))))
