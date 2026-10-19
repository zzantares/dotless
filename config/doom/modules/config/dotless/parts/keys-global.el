;;; parts/keys-global.el -*- lexical-binding: t; -*-

(map! :g "C-s" #'save-buffer)
(map! :g "M-," #'zz/goto-doom-config-file)
(map! :m "M-," #'zz/goto-doom-config-file)
(map! :map helpful-mode-map :n "o" #'push-button)
(map! :map comint-mode-map
      :i "C-p" #'comint-previous-input
      :i "C-n" #'comint-next-input
      :i "C-k" #'comint-next-input
      :i "C-h" #'comint-previous-input
      :i "C-l" #'comint-clear-buffer)
(add-hook! 'Info-mode-hook
  (map! :map Info-mode-map :nv "o" #'Info-follow-nearest-node))
