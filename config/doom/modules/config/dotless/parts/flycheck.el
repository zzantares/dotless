;;; parts/flycheck.el -*- lexical-binding: t; -*-

(after! flycheck
  (map! :prefix "]" :desc "Next error" :m "e" #'flycheck-next-error)
  (map! :prefix "[" :desc "Next error" :m "e" #'flycheck-previous-error))
