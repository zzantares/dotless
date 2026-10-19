;;; parts/clojure.el -*- lexical-binding: t; -*-

(after! cider
  (add-hook! clojure-mode
    (add-hook! 'after-save-hook :local #'cider-ns-refresh))
  (require 'kaocha-runner)
  (setopt cider-save-file-on-load t
         cider-ns-save-files-on-refresh t)
  ;; TODO `i` should handle when cursor is in read-only vs writable region
  (map! :map cider-repl-mode-map :n "i" #'evil-goto-line)
  (map! :map cider-repl-mode-map :ni "C-p" #'cider-repl-backward-input)
  (map! :map cider-repl-mode-map :ni "C-n" #'cider-repl-next-input)
  (map! :map cider-mode-map :localleader :prefix "t"
        :desc "Kaocha test at point" :nv "T" #'kaocha-runner-run-test-at-point
        :desc "Kaocha test ns" :nv "N" #'kaocha-runner-run-tests
        :desc "Kaocha test project" :nv "P" #'kaocha-runner-run-all-tests))
