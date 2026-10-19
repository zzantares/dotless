;;; parts/spell-fu.el -*- lexical-binding: t; -*-

(add-hook! yaml-mode
           #'(lambda ()
               ;; in yaml-mode attributes/keys seem to be recognized as strings and thus spell checked which isn't very useful
               ;; but if there could be a face for yaml attributes then we could add that face into the list of excluded faces
               ;; and we could check for spelling in actual strings and comments in YAML files
               (spell-fu-mode -1)))

(after! spell-fu
  ;; TODO workround for https://github.com/doomemacs/doomemacs/issues/6246
  ;; Ensure personal dictionary files exist for each language in use.
  (dolist (lang (list ispell-dictionary "es"))
    (let ((pws (expand-file-name (format "ispell/%s.pws" lang) doom-data-dir)))
      (unless (file-exists-p pws)
        (make-directory (file-name-directory pws) t)
        (with-temp-file pws
          (insert (format "personal_ws-1.1 %s 0\n" lang)))))))

(add-hook! 'spell-fu-mode-hook
           #'(lambda ()
               (spell-fu-dictionary-add (spell-fu-get-ispell-dictionary "es"))))
