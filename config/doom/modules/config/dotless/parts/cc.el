;;; parts/cc.el -*- lexical-binding: t; -*-

(add-hook! c-mode
  (add-to-list 'c-default-style '(c-mode . "bsd"))
  (add-to-list 'c-default-style '(cc-mode . "bsd"))
  (set-formatter!
    'clang-format
    '("clang-format" "--style" "Webkit" "--assume-filename"
      (or
       (buffer-file-name)
       ".c"))
    :modes '(c-mode)))
(after! c-mode
  (map! :map c-mode-map :localleader :m "h" #'woman-follow)
  (map! :map c-mode-map :localleader :m "H" #'woman))
