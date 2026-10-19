;;; parts/org-keys.el -*- lexical-binding: t; -*-

(after! evil-org
  (map! :map evil-org-mode-map
        :nvi "M-h" #'org-metaup
        :nvi "M-k" #'org-metadown
        :nvi "M-j" #'org-metaleft
        :nvi "M-l" #'org-metaright
        :nvi "M-H" #'org-shiftmetaup
        :nvi "M-K" #'org-shiftmetadown
        :nvi "M-J" #'org-shiftmetaleft
        :nvi "M-L" #'org-shiftmetaright
        :nv "g k" #'evil-next-visual-line
        :nv "g h" #'evil-previous-visual-line
        :nv "g K" #'org-forward-element
        :nv "g H" #'org-backward-element
        :nv "g J" #'org-up-element
        :nv "C-k" #'org-forward-element
        :nv "C-h" #'org-backward-element
        :nv "C-j" #'org-up-element
        :nv "C-l" #'org-down-element))

(after! evil-org-agenda
  (map! :map evil-org-agenda-mode-map :m "o" #'org-agenda-switch-to)
  (map! :map evil-org-agenda-mode-map :m "k" #'org-agenda-next-line)
  (map! :map evil-org-agenda-mode-map  :m "h" #'org-agenda-previous-line)
  ;; Disables 'j' and 'l' so that evil-motion bindings are used for left and right movement
  (map! :map evil-org-agenda-mode-map :m "j" nil)
  (map! :map evil-org-agenda-mode-map :m "l" nil)
  (map! :map evil-org-agenda-mode-map :m "M-h" #'org-agenda-drag-line-backward)
  (map! :map evil-org-agenda-mode-map :m "M-k" #'org-agenda-drag-line-backward))

(after! org-crypt
  (setq org-crypt-key user-mail-address))

(add-hook! (org-mode markdown-mode git-commit-mode)
           #'(lambda ()
               (set-fill-column 78)
               (auto-fill-mode 1)))
