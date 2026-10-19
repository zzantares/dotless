;;; parts/forge.el -*- lexical-binding: t; -*-

(after! forge
  ;; store forge database outside of ~/.config/emacs/.local since we re-install emacs often and we loose it
  ;; TODO we could instea dmake the upgrade recipe to temporarily backup ~/.config/emacs/.local/etc/forge/forge-database.sqlite
  (setopt forge-database-file
         (expand-file-name "doom/forge-database.sqlite"
                           (or (getenv "XDG_DATA_HOME") "~/.local/share")))
  (add-to-list 'forge-alist '("gitlab.haskell.org" "gitlab.haskell.org/api/v4" "gitlab.haskell.org" forge-gitlab-repository)))
