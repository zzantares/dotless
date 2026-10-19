;;; parts/auto-mode.el -*- lexical-binding: t; -*-

;; TODO what's the doom way to configure this?
(add-to-list 'auto-mode-alist '("\\.vim\\(rc\\)?\\'" . vimrc-mode))
(add-to-list 'auto-mode-alist '("\\.nomad\\(?:\\.tftpl\\)?\\'" . hcl-mode))
