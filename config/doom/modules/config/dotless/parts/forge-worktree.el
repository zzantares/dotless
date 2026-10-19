;;; parts/forge-worktree.el -*- lexical-binding: t; -*-

(defun zz-forge-checkout-worktree (orig-fun &rest orig-args)
  "Meant to be used as an advice to `forge-checkout-worktree' in which the
created worktree is added as a projectile project and switch to it after
checkout, and diff-hl is pointed at the PR's base so the worktree files are
annotated with the PR's changes."
  (forge-pull)
  (let ((the-path (car orig-args))
        (the-pullreq (nth 1 orig-args))
        (+workspaces-switch-project-function #'(lambda (the-project-path)
                                                 (magit-status-setup-buffer the-project-path)
                                                 (lsp-workspace-folders-add the-project-path)))
        (+workspaces-switch-project-function #'magit-status))
    (apply orig-fun orig-args)
    (projectile-add-known-project the-path)
    (projectile-switch-project-by-name the-path)
    (when (fboundp 'revu-diff-hl-set-from-pullreq)
      (revu-diff-hl-set-from-pullreq the-path the-pullreq))))

(advice-add 'forge-checkout-worktree :around #'zz-forge-checkout-worktree)

(defun zz-projectile-invalidate-cache (&rest _args)
  "We want to invalidate projectile cache after checking out a branch since
files might be at different locations."
  ;; We ignore the args to `magit-checkout' (the adviced function).
  (projectile-invalidate-cache nil))

(advice-add 'magit-checkout :after #'zz-projectile-invalidate-cache)
(advice-add 'magit-branch-and-checkout :after #'zz-projectile-invalidate-cache)
