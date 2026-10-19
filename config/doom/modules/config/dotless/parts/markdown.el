;;; parts/markdown.el -*- lexical-binding: t; -*-

(after! markdown
  (map! :map markdown-mode-map :m "M-h" #'markdown-move-up)
  (map! :map markdown-mode-map :m "M-k" #'markdown-move-down))

(after! evil-markdown
  (map! :map evil-markdown-mode-map
        :nv "g k" #'evil-next-visual-line
        :nv "g h" #'evil-previous-visual-line))
