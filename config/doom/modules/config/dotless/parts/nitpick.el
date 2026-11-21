;;; parts/nitpick.el -*- lexical-binding: t; -*-

;; `nitpick' ships from dotless; soft-required so this config still loads on a
;; machine whose flake predates it.
(when (require 'nitpick nil t)
  (nitpick-forge-mode 1)
  ;; without it diff-hl marks the wrong lines: see its docstring
  (nitpick-diff-hl-zero-context-mode 1)
  ;; RET on a removed line opens the base's blob, not the file without it
  (nitpick-diff-visit-base-mode 1)
  ;; The two visit keys, in magit's own section maps: RET opens the version the
  ;; line at point belongs to, S-RET the other one. Those maps are text-property
  ;; keymaps, which outrank any minor mode's, so this is the only place to say
  ;; it - and it has to be said after evil-collection-magit, which points RET
  ;; at `magit-diff-visit-worktree-file' and so loses the base side.
  (defun +dotless-nitpick-bind-visit-keys ()
    (dolist (map (list magit-file-section-map magit-hunk-section-map))
      (define-key map (kbd "RET") #'nitpick-visit)
      (define-key map (kbd "S-<return>") #'nitpick-visit-other)))
  (after! magit (+dotless-nitpick-bind-visit-keys))
  (after! evil-collection-magit (+dotless-nitpick-bind-visit-keys))

  ;; the changed-file pane; a second feature, and nix ships no autoloads
  (when (require 'nitpick-tree nil t)
    ;; `nitpick-pr' opens a PR in that pane without checking it out
    (require 'nitpick-pr nil t)
    ;; `nitpick-tree-mode-map' alone never sees `d': treemacs' evil state
    ;; enables motion state, which suppresses plain letters. An auxiliary map
    ;; on the minor mode is what evil consults first.
    ;; `r' but not `g': `g' is a prefix in motion state, and taking it would
    ;; cost `gg'. Non-evil users get `g' from the mode map itself.
    ;; `o' is treemacs' prefix for opening a node in a split. Here the other
    ;; window is the diff, so splitting it is the friction the pane removes.
    (after! treemacs-evil
      (evil-define-key 'treemacs nitpick-tree-mode-map
        (kbd "d") #'nitpick-tree-visit-diff
        (kbd "o") #'nitpick-tree-visit
        (kbd "O") #'nitpick-tree-visit-other
        (kbd "f") #'nitpick-tree-toggle-follow
        (kbd "N") #'nitpick-tree-toggle-narrow
        (kbd "r") #'nitpick-tree-refresh
        (kbd "q") #'nitpick-tree-close))))
