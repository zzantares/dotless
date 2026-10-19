;;; parts/spell.el -*- lexical-binding: t; -*-

(setq ispell-dictionary "en")
;; Doom sets ispell-personal-dictionary based on the global ispell-dictionary
;; ("en.pws"). When a buffer uses a different local dictionary (e.g. "es"),
;; aspell reads en.pws, sees the "en" header mismatch, and errors. Fix: after
;; file-local variables are applied, update the personal dict to match.
(add-hook 'hack-local-variables-hook
  (lambda ()
    (when (and (boundp 'ispell-local-dictionary) ispell-local-dictionary)
      (setq-local ispell-personal-dictionary
                  (expand-file-name
                   (format "ispell/%s.pws" ispell-local-dictionary)
                   doom-data-dir)))))
