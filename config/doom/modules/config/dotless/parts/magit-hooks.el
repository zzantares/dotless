;;; parts/magit-hooks.el -*- lexical-binding: t; -*-

(add-hook! 'magit-process-mode-hook
           ;; so that pressing '`' again doesn't open a second magit-process buffer but closes the existing one
           (map! :map magit-process-mode-map :nv "`" #'+magit/quit))

(add-hook! 'magit-section-movement-hook 'magit-log-maybe-update-blob-buffer)
(add-hook! 'magit-blame-read-only-mode-hook
           #'(lambda ()
               (map! :map magit-blame-read-only-mode-map :nv "k" #'evil-next-line)
               (map! :map magit-blame-read-only-mode-map :nv "h" #'evil-previous-line)
               (map! :map magit-blame-read-only-mode-map :nv "C-k" #'magit-blame-next-chunk)
               (map! :map magit-blame-read-only-mode-map :nv "C-h" #'magit-blame-previous-chunk)
               (map! :map magit-blame-read-only-mode-map :nv "C-e" #'evil-scroll-line-down)
               (map! :map magit-blame-read-only-mode-map :nv "C-y" #'evil-scroll-line-up)
               (map! :map magit-blame-read-only-mode-map :nv "g K" #'magit-blame-next-chunk-same-commit)
               (map! :map magit-blame-read-only-mode-map :nv "g H" #'magit-blame-previous-chunk-same-commit)
               (map! :map magit-blame-read-only-mode-map :nv "g k" #'magit-blame-next-chunk)
               (map! :map magit-blame-read-only-mode-map :nv "g h" #'magit-blame-previous-chunk)))
(add-hook! 'git-rebase-mode-hook
           #'(lambda ()
               (map! :map git-rebase-mode-map :nv "k" #'evil-next-line)
               (map! :map git-rebase-mode-map :nv "h" #'evil-previous-line)
               (map! :map git-rebase-mode-map :nv "gk" #'git-rebase-move-line-down)
               (map! :map git-rebase-mode-map :nv "gh" #'git-rebase-move-line-up)
               (map! :map git-rebase-mode-map :nv "C-k" #'git-rebase-move-line-down)
               (map! :map git-rebase-mode-map :nv "C-h" #'git-rebase-move-line-up)))

(map! :map '(magit-status-mode-map forge-topic-mode-map)
      :leader
      :desc "Start code review"
      :g "g v" '+magit/start-code-review)

;; (map! :map magit-status-mode-map :nv "RET" #'forge-visit-topic) ; this also overrides visiting diff at point we don't want that

(add-hook! 'magit-status-mode-hook
  (projectile-add-known-project (magit-toplevel)))

(add-hook! 'forge-post-mode-hook
  (auto-fill-mode -1))
