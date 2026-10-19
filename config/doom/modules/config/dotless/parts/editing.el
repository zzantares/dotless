;;; parts/editing.el -*- lexical-binding: t; -*-

(setq-default line-spacing 3
              indent-tabs-mode nil
              tab-width 4)

(setq +format-on-save-disabled-modes
      '(not
        emacs-lisp-mode                 ; lispy does formatting
        tex-mode                        ; latexindent is broken
        latex-mode
        jinja2-mode                     ; prettier treats it as HTML and it mungles Ansible templates e.g. systemd units templates
        yaml-mode))
