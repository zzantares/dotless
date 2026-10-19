;;; parts/vertico.el -*- lexical-binding: t; -*-

(after! vertico
  (map! :when (modulep! :editor evil +everywhere)
        :map vertico-map
        "C-k"   #'vertico-next
        "C-M-k" #'vertico-next-group
        "C-h"   #'vertico-previous
        "C-M-h" #'vertico-previous-group
        "C-j" (cmds! (eq 'file (vertico--metadata-get 'category)) #'vertico-directory-up)))
