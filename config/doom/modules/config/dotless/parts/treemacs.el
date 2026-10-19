;;; parts/treemacs.el -*- lexical-binding: t; -*-

(add-hook! '(treemacs-mode-hook evil-treemacs-state-entry-hook) #'hide-mode-line-mode)

(defun zz-treemacs-create (dir?)
  "Create a file at point, or a directory with a prefix arg DIR?."
  (interactive "P")
  (if dir? (treemacs-create-dir) (treemacs-create-file)))

(after! treemacs-evil
  (setopt treemacs-width 40)
  (evil-define-key 'treemacs treemacs-mode-map (kbd "h") #'treemacs-previous-line)
  ;; `TAB', `u', `R' and `q' already match dired. These add the rest of it,
  ;; dropping treemacs' `o' visit-in-split prefix and `m' treemacs-move-file
  (map! :map (treemacs-mode-map evil-treemacs-state-map)
        "k" #'treemacs-next-line
        "h" #'treemacs-previous-line
        "l" #'treemacs-RET-action
        "j" #'treemacs-COLLAPSE-action
        "o" #'treemacs-RET-action
        "+" #'zz-treemacs-create
        "D" #'treemacs-delete-file
        "ma" #'zz-treemacs-create
        "md" #'treemacs-delete-file
        "mm" #'treemacs-rename-file
        "M-k" #'treemacs-next-neighbour
        "M-h" #'treemacs-previous-neighbour
        "M-J" #'treemacs-root-up
        "M-L" #'treemacs-root-down
        "M-K" #'treemacs-next-line-other-window
        "M-H" #'treemacs-previous-line-other-window))
