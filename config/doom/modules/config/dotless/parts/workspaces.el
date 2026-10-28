;;; parts/workspaces.el -*- lexical-binding: t; -*-

;; A workspace holds no directory of its own, so switching to a blank one
;; leaves you on the previous buffer and `:pwd' still reports the old project.
;; Doom records the root of a workspace it made by project switch; `git wt
;; start' records the worktree the same way. Land in it on the way in.
(after! persp-mode
  (defun zz/workspace-visit-project-h (&rest _)
    "Open the project recorded on the activated workspace.
Does nothing when the workspace has no recorded root, or point is already
inside it."
    (let ((root (persp-parameter '+workspace-project)))
      (when (and root
                 (fboundp 'projectile-switch-project-by-name)
                 (file-directory-p root)
                 (not (file-in-directory-p default-directory root)))
        ;; dired, not Doom's own action: that one creates a second workspace
        ;; for the project, and its default prompts - this also runs headless,
        ;; on session restore, where a prompt parks the daemon's main thread.
        (let ((projectile-switch-project-action #'projectile-dired))
          (ignore-errors (projectile-switch-project-by-name root))))))

  (add-hook 'persp-activated-functions #'zz/workspace-visit-project-h))
