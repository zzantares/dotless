;;; parts/nitpick.el -*- lexical-binding: t; -*-

;; `nitpick' ships from dotless; soft-required so this config still loads on a
;; machine whose flake predates it.
(when (require 'nitpick nil t)
  (nitpick-forge-mode 1))
