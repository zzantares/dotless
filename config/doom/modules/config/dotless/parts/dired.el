;;; parts/dired.el -*- lexical-binding: t; -*-

(after! dired
  (map! :leader :prefix "t" :desc "Dired at this location" :nv "t" #'dired-jump)
  (map! :mode dired :map dired-mode-map :n "k" #'dired-next-line)
  (map! :mode dired :map dired-mode-map :n "h" #'dired-previous-line)
  (map! :mode dired :map dired-mode-map :n "o" #'dired-find-file)
  (map! :mode dired :map dired-mode-map :n "u" #'dired-up-directory))

(after! (:and dired persp-mode)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "New workspace" :n "c" #'+workspace/new)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "Delete workspace" :n "x" #'+workspace/kill)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "Switch to other workspace" :nv "t" #'+workspace/other)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "Switch to workspace" :nv "T" #'+workspace/switch-to)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "New workspace" :n "C-c" #'+workspace/new)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "Delete workspace" :n "C-x" #'+workspace/kill)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "Switch to other workspace" :nv "C-t" #'+workspace/other))

(after! dirvish
  (map! :map dirvish-mode-map :n "k" #'dired-next-line)
  (map! :map dirvish-mode-map :n "h" #'dired-previous-line)
  (map! :map dirvish-mode-map :n "o" #'dired-find-file)
  (map! :map dirvish-mode-map :n "u" #'dired-up-directory))
