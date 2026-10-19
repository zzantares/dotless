;;; parts/auth.el -*- lexical-binding: t; -*-

(setq auth-sources
      (list (concat (file-name-as-directory (getenv "DOTFILES_FLAKE_ROOT"))
                    (format "secrets/%s/.authinfo.gpg" user-login-name))))
