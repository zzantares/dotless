;;; parts/projectile.el -*- lexical-binding: t; -*-

(after! projectile
  (defun zz/projectile-package-dir ()
    "Open closest package directory found upwards starting from `default-directory'."
    (interactive)
    (let ((package-dir (projectile-locate-dominating-file default-directory #'zz/is-package-dir)))
      (when package-dir (dired package-dir))))
  (defun zz/projectile-package-file ()
    "Open closest package file found upwards starting from `default-directory'."
    (interactive)
    (let ((package-dir (projectile-locate-dominating-file default-directory #'zz/is-package-dir)))
      (when package-dir
        (find-file (zz/is-package-dir package-dir)))))

  ;; TODO WIP function to quickly watch a build using vterm
  ;; (defun zz/tester ()
  ;;   (let* ((project-name (funcall extract-project-name project-file))
  ;;          (cmd (funcall build-command project-name))
  ;;          (buffer-name (concat "*watcher-" project-name "*")))
  ;;     ;; Open or switch to vterm buffer
  ;;     (let ((vterm-buffer (get-buffer buffer-name)))
  ;;       (if vterm-buffer
  ;;           (switch-to-buffer vterm-buffer)
  ;;         (setq vterm-buffer (vterm buffer-name)))
  ;;       ;; Run the command in the terminal
  ;;       (vterm-send-string cmd)
  ;;       (vterm-send-return)))
  ;;   )

  ;; store projectile projects outside of ~/.config/emacs/.local since we re-install emacs often and we loose it
  ;; TODO we could instead make the upgrade recipe to temporarily backup  ~/.config/emacs/.local/cache/projectile/projects.eld
  (setopt projectile-known-projects-file
          (expand-file-name "doom/projectile-projects.eld"
                            (or (getenv "XDG_DATA_HOME") "~/.local/share")))
  (map! :leader :prefix "t" :desc "Dired at project root" :nv "r" #'projectile-dired)
  (map! :leader :prefix "t" :desc "Dired at package root" :nv "p" #'zz/projectile-package-dir)
  (map! :map projectile-command-map :leader :prefix "p" :desc "Kill ongoing compilation" :nv "K" #'kill-compilation)
  (map! :nv "C-p" #'projectile-find-file)
  (map! :localleader :desc "Package description file" :nv "," #'zz/projectile-package-file))

(after! simple
  (map! :map special-mode-map :desc "Quit" :nv "q" #'quit-window))
