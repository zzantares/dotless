;;; parts/nitpick.el -*- lexical-binding: t; -*-

;; `nitpick' ships from dotless; soft-required so this config still loads on a
;; machine whose flake predates it.
(when (require 'nitpick nil t)
  (nitpick-forge-mode 1)
  ;; without it diff-hl marks the wrong lines: see its docstring
  (nitpick-diff-hl-zero-context-mode 1))
