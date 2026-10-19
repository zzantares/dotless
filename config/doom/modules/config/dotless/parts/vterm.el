;;; parts/vterm.el -*- lexical-binding: t; -*-

;; TODO Variables manually set work but with the hook it seems they get ignored? explore the keymaps
(after! vterm
  (when (file-exists-p "~/.nix-profile/bin/zsh")
    (setopt vterm-shell (expand-file-name "~/.nix-profile/bin/zsh")))
  (defun zz-vterm-reset-cursor-point-insert ()
    (interactive)
    (let ((prompt-line (save-excursion
                         (vterm-reset-cursor-point)
                         (what-line))))
      (if (string= (what-line) prompt-line)
          (evil-collection-vterm-insert)
        (vterm-reset-cursor-point)
        (vterm-send-key (kbd "C-e"))
        (evil-collection-vterm-insert))))
  (map! :map vterm-mode-map :n "M-:" #'eval-expression)
  (map! :map vterm-mode-map :n "q" #'zz-vterm-reset-cursor-point-insert)
  (map! :map vterm-mode-map :v "q" #'(lambda ()
                                       (interactive)
                                       (evil-exit-visual-state)
                                       (zz-vterm-reset-cursor-point-insert)))
  (map! :map vterm-mode-map :prefix "C-t" :i "[" #'evil-normal-state)
  (map! :map vterm-mode-map :prefix "C-t" :ni "]" #'evil-collection-vterm-paste-after)
  (map! :map vterm-mode-map :n "i" #'zz-vterm-reset-cursor-point-insert)
  (map! :map vterm-mode-map :nv "k" #'evil-collection-vterm-next-line)
  (map! :map vterm-mode-map :nv "l" #'evil-forward-char)
  (map! :map vterm-mode-map :nv "j" #'evil-backward-char))

(add-hook! vterm-mode :local
  (setopt evil-normal-state-cursor '(box "cornsilk"))
  (setopt evil-insert-state-cursor '(box "DarkGoldenrod")))

(add-hook! vterm-mode
  (display-line-numbers-mode -1)
  (compilation-shell-minor-mode))

(after! (:or compile vterm)
  (map! :map compilation-shell-minor-mode-map :prefix "g" :n "." #'compilation-next-error-function))
