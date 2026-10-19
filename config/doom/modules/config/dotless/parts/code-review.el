;;; parts/code-review.el -*- lexical-binding: t; -*-

(add-hook! 'code-review-mode-hook
  (map! :map code-review-mode-map :nv "k" #'evil-next-line)
  (map! :map code-review-mode-map :nv "h" #'evil-previous-line))
(add-hook! 'code-review-mode-hook
           #'(lambda ()
               ;; include *Code-Review* buffer into current workspace
               (persp-add-buffer (current-buffer))))
