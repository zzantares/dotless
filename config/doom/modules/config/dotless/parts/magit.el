;;; parts/magit.el -*- lexical-binding: t; -*-

(after! magit
  (setopt magit-log-section-commit-count 20)
  (setf (alist-get 'unpushed magit-section-initial-visibility-alist) 'show) ;; auto-expand recent commits section
  ;; TODO theres a new undocumented filtering mechanism that replaces the section hooks see: https://github.com/magit/forge/issues/676
  ;; (magit-add-section-hook 'magit-status-sections-hook #'forge-insert-requested-reviews 'forge-insert-pullreqs nil)
  ;; (magit-add-section-hook 'magit-status-sections-hook #'forge-insert-assigned-pullreqs 'forge-insert-pullreqs nil)
  ;; (magit-add-section-hook 'magit-status-sections-hook #'forge-insert-assigned-issues 'forge-insert-pullreqs)
  ;; (magit-add-section-hook 'magit-status-sections-hook #'forge-insert-authored-issues 'forge-insert-issues nil)
  ;; TODO This setting doesn't look right because of line height images look odd
  (setq magit-revision-show-gravatars '("^Author:     " . "^Commit:     "))
  (map! :map magit-mode-map "C-t" nil)  ; pass-through to global map
  (map! :map magit-mode-map :nv "k" #'evil-next-visual-line)
  (map! :map magit-mode-map :nv "h" #'evil-previous-visual-line)
  (map! :map magit-mode-map :nv "n" #'magit-section-forward)
  (map! :map magit-mode-map :nv "p" #'magit-section-backward)
  (map! :map magit-mode-map :nv "C-n" #'magit-section-forward)
  (map! :map magit-mode-map :nv "C-p" #'magit-section-backward)
  (map! :map magit-mode-map :nv "C-k" #'magit-section-forward)
  (map! :map magit-mode-map :nv "C-h" #'magit-section-backward)
  (map! :map magit-mode-map :prefix "C-w" :nv "k" #'evil-window-down)
  (map! :map magit-mode-map :prefix "C-w" :nv "h" #'evil-window-up)
  (map! :map magit-mode-map :prefix "C-w" :nv "j" #'evil-window-left)
  (map! :map magit-mode-map :prefix "C-w" :nv "l" #'evil-window-right)
  (map! :map magit-mode-map :localleader :m "h" #'magit-smerge-keep-upper)
  (map! :map magit-mode-map :localleader :m "k" #'magit-smerge-keep-lower)
  (map! :map magit-mode-map :localleader :m "a" #'magit-smerge-keep-all)
  (map! :map magit-mode-map :localleader :m "n" #'magit-smerge-keep-base)
  (map! :map magit-mode-map :localleader :m "g" #'magit-smerge-keep-current)
  ;; TODO These workspace bindings are basically duplicated, need to fix that
  (map! :map magit-mode-map :prefix "C-t" :desc "New workspace" :nv "c" #'+workspace/new)
  (map! :map magit-mode-map :prefix "C-t" :desc "Delete workspace" :nv "x" #'+workspace/kill)
  (map! :map magit-mode-map :prefix "C-t" :desc "Next workspace" :nv "n" #'+workspace/switch-right)
  (map! :map magit-mode-map :prefix "C-t" :desc "Previous workspace" :nv "p" #'+workspace/switch-left)
  (map! :map magit-mode-map :prefix "C-t" :desc "Switch to workspace" :nv "T" #'+workspace/switch-to)
  (map! :map magit-mode-map :prefix "C-t" :desc "Switch to workspace" :nv "t" #'+workspace/other)
  (map! :map magit-mode-map :prefix "g" :desc "Switch to other workspace" :nv "t" #'+workspace/other)
  (map! :map magit-mode-map :prefix "C-t" :desc "Load workspace from file" :nv "L" #'+workspace/load)
  (map! :map magit-mode-map :prefix "C-t" :desc "List workspaces" :nv "l" #'+workspace/switch-to)
  (map! :map magit-mode-map :prefix "C-t" :desc "List workspaces" :nv "R" #'+workspace/restore-last-session)
  (map! :map magit-mode-map :prefix "C-t" :desc "Rename workspace" :nv "r" #'+workspace/rename)
  (map! :map magit-mode-map :prefix "C-t" :desc "Rename workspace" :nv "," #'+workspace/rename)
  (map! :map magit-mode-map :prefix "C-t" :desc "New workspace" :nv "C-c" #'+workspace/new)
  (map! :map magit-mode-map :prefix "C-t" :desc "Delete workspace" :nv "C-x" #'+workspace/kill)
  (map! :map magit-mode-map :prefix "C-t" :desc "Next workspace" :nv "C-n" #'+workspace/switch-right)
  (map! :map magit-mode-map :prefix "C-t" :desc "Previous workspace" :nv "C-p" #'+workspace/switch-left)
  (map! :map magit-mode-map :prefix "C-t" :desc "Switch to other workspace" :nv "C-t" #'+workspace/other)
  (map! :map magit-mode-map :prefix "C-t" :desc "Load workspace from file" :nv "C-L" #'+workspace/load)
  (map! :map magit-mode-map :prefix "C-t" :desc "List workspaces" :nv "C-l" #'+workspace/switch-to)
  (map! :map magit-mode-map :prefix "C-t" :desc "List workspaces" :nv "C-R" #'+workspace/restore-last-session)
  (map! :map magit-mode-map :prefix "C-t" :desc "Rename workspace" :nv "C-r" #'+workspace/rename)
  (map! :map magit-mode-map :prefix "C-t" :desc "Rename workspace" :nv "C-," #'+workspace/rename)
  (map! :map magit-diff-mode-map :prefix "C-w" :nv "k" #'evil-window-down)
  (map! :map magit-diff-mode-map :prefix "C-w" :nv "h" #'evil-window-up)
  (map! :map magit-diff-mode-map :prefix "C-w" :nv "j" #'evil-window-left)
  (map! :map magit-diff-mode-map :prefix "C-w" :nv "l" #'evil-window-right)
  (map! :leader :prefix "g" :desc "Diff buffer file" :m "d" #'magit-diff-buffer-file)
  (map! :leader :prefix "g" :desc "Push a branch" :m "P" #'magit-push)
  (map! :leader :prefix "g" :desc "Pull a branch" :m "p" #'magit-pull)
  (map! :leader :prefix "g" :desc "PR to worktree" :m "w" #'forge-checkout-worktree)
  (map! :leader :prefix "g" (:prefix "W" :desc "Delete worktree" :m "k" #'magit-worktree-delete))
  (map! :leader :prefix "g" (:prefix "W" :desc "Move worktree" :m "m" #'magit-worktree-move))
  (map! :leader :prefix "g" (:prefix "c" :desc "Checkout branch" :m "o" #'magit-branch-checkout))
  (map! :leader :prefix "g" (:prefix "l" :desc "Git log at branch" :m "l" #'magit-log-current))
  (map! :leader :prefix "g" (:prefix "c" :desc "Amend commit" :m "a" #'magit-commit-amend))
  ;; PR review commands live under the "V" (reView) prefix: "R" is already
  ;; Doom's `vc-revert' and "r" is `+vc-gutter/save-and-revert-hunk', so neither
  ;; can be a prefix. The cons label makes which-key show "review".
  ;;
  ;; One `map!' for the whole group, and it has to stay that way: a cons-label
  ;; prefix builds a fresh keymap on every call, so a second `map!' naming
  ;; ("V" . "review") discards what the first bound. A plain string prefix
  ;; merges; this one cannot.
  (map! :leader :prefix "g"
        (:prefix ("V" . "review")
         :desc "Comment on PR line(s)"     :m "c" #'nitpick-comment
         :desc "List pending review"       :m "l" #'nitpick-list
         :desc "Submit review (comment)"   :m "s" #'nitpick-submit
         :desc "Refresh review to PR head" :m "f" #'nitpick-refresh
         :desc "Set the diff base"         :m "b" #'nitpick-diff-hl-set-base
         :desc "Paint changed lines"       :m "H" #'nitpick-diff-hl-line-mode)))

(after! agitjo
  (agitjo-setup "#"))
