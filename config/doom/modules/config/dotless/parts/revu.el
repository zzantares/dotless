;;; parts/revu.el -*- lexical-binding: t; -*-

;; `revu' ships from dotless; soft-required so this config still loads on a
;; machine whose flake predates it.
(when (require 'revu nil t)
  (revu-forge-mode 1))
