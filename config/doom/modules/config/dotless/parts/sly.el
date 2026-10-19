;;; parts/sly.el -*- lexical-binding: t; -*-

(after! sly
  ;; TODO This function is not sly specific, could be used for vterm as well
  (defun zz/insert-on-repl ()
    (interactive)
    (evil-goto-line)
    (evil-append-line 1))
  (map! :map sly-mrepl-mode-map :i "C-r" #'isearch-backward)
  (map! :map sly-mrepl-mode-map :i "C-l" #'evil-scroll-line-to-top)
  (map! :map sly-mrepl-mode-map :i "C-k" #'kill-line)
  (map! :map sly-mrepl-mode-map :i "C-p" #'sly-mrepl-previous-input-or-button)
  (map! :map sly-mrepl-mode-map :i "C-n" #'sly-mrepl-next-input-or-button)
  (map! :map sly-mrepl-mode-map :n "q" #'zz/insert-on-repl)
  (map! :map sly-mrepl-mode-map :n "i" #'zz/insert-on-repl))
