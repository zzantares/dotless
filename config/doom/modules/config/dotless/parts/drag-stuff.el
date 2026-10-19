;;; parts/drag-stuff.el -*- lexical-binding: t; -*-

(after! drag-stuff
  (map! :map drag-stuff-mode-map :desc "Drag stuff up" :nv "M-h" #'drag-stuff-up)
  (map! :map drag-stuff-mode-map :desc "Drag stuff up" :nv "M-k" #'drag-stuff-down))
