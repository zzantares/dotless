;;; parts/forge-worktree.el -*- lexical-binding: t; -*-

(defun zz-forge-checkout-worktree (orig-fun &rest orig-args)
  "Meant to be used as an advice to `forge-checkout-worktree' in which the
created worktree is added as a projectile project and an lsp workspace folder
and switch to it after checkout, and diff-hl is pointed at the PR's base so the
worktree files are annotated with the PR's changes."
  (forge-pull)
  (let ((the-path (car orig-args))
        ;; `forge-read-pullreq' hands over an id, not the object.
        (the-pullreq (forge-get-pullreq (nth 1 orig-args)))
        (+workspaces-switch-project-function #'magit-status))
    (apply orig-fun orig-args)
    (projectile-add-known-project the-path)
    (projectile-switch-project-by-name the-path)
    ;; Not autoloaded, so only once lsp-mode is up.
    (when (fboundp 'lsp-workspace-folders-add)
      (lsp-workspace-folders-add the-path))
    (when (fboundp 'nitpick-diff-hl-set-from-pullreq)
      (nitpick-diff-hl-set-from-pullreq the-path the-pullreq))))

(advice-add 'forge-checkout-worktree :around #'zz-forge-checkout-worktree)

(defun zz-forge-checkout-worktree-read-directory (pullreq)
  "Read the worktree directory for PULLREQ, defaulting to <number>-<branch>.
Same as Forge's own default, minus its crash when the PR's source branch is
gone: head-ref is then nil (GitHub) or \":branch\" (Gitlab), and Forge feeds
that straight to `string-match-p'. Those PRs default to the number alone."
  (let* ((number (oref pullreq number))
         (branch (forge--pullreq-branch-internal pullreq))
         (default (if (or (null branch)
                          (string-match-p "\\`pr-[0-9]+\\'" branch))
                      (number-to-string number)
                    (format "%s-%s" number (string-replace "/" "-" branch))))
         (path (read-directory-name
                (format "Checkout #%s in new worktree: " number)
                (file-name-directory (directory-file-name default-directory))
                nil nil default)))
    (when (equal path "")
      (user-error "The empty string isn't a valid path"))
    path))

(after! forge
  (setopt forge-checkout-worktree-read-directory-function
          #'zz-forge-checkout-worktree-read-directory))

(defun zz-projectile-invalidate-cache (&rest _args)
  "We want to invalidate projectile cache after checking out a branch since
files might be at different locations."
  ;; We ignore the args to `magit-checkout' (the adviced function).
  (projectile-invalidate-cache nil))

(advice-add 'magit-checkout :after #'zz-projectile-invalidate-cache)
(advice-add 'magit-branch-and-checkout :after #'zz-projectile-invalidate-cache)
