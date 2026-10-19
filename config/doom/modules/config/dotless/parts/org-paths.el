;;; parts/org-paths.el -*- lexical-binding: t; -*-

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/Documents/org/")
(setq org-agenda-files '("~/Documents/org/agenda.org" "~/Documents/org/todo.org"))
(setq +org-capture-journal-file (concat +org-capture-journal-file ".gpg"))
