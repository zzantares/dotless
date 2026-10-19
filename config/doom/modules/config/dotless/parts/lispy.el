;;; parts/lispy.el -*- lexical-binding: t; -*-

(add-hook! lispyville-mode
  (map! :map lispyville-mode-map
        :n "M-h" #'drag-stuff-up
        :n "M-k" #'drag-stuff-down
        :n "M-j" #'lispyville-drag-backward
        :n "M-l" #'lispyville-drag-forward))

(add-hook! lisp-data-mode
  (lispy-mode 1)
  (lispyville-mode 1))
