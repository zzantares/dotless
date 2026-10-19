;;; parts/pdf.el -*- lexical-binding: t; -*-

(add-hook! pdf-view-mode
  (map! :map pdf-view-mode-map
        :nv "l" #'image-forward-hscroll
        :nv "j" #'image-backward-hscroll
        :nv "k" #'pdf-view-next-line-or-next-page
        :nv "h" #'pdf-view-previous-line-or-previous-page))
