;;; parts/smerge.el -*- lexical-binding: t; -*-

(after! smerge-mode
  ;; TODO these C-* bindings don't work apparently the smerge map has lower priority
  (map! :mode smerge-mode :map smerge-basic-map :m "C-l" #'smerge-vc-next-conflict)
  (map! :mode smerge-mode :map smerge-basic-map :m "C-j" #'smerge-prev)
  (map! :mode smerge-mode :map smerge-basic-map :m "C-h" #'smerge-keep-upper)
  (map! :mode smerge-mode :map smerge-basic-map :m "C-k" #'smerge-keep-lower)
  (map! :mode smerge-mode :map smerge-basic-map :m "C-RET" #'smerge-keep-all)
  (map! :mode smerge-mode :map smerge-basic-map :m "C-x" #'smerge-keep-base)
  (map! :mode smerge-mode :map smerge-basic-map :m "C-c" #'smerge-keep-current)
  (map! :localleader :desc "Smerge git conflicts" "g" smerge-basic-map))

(add-hook! smerge-mode
  (flycheck-mode -1)
  ;; TODO Possibly need to unbind in web-mode or at least in ts mode (test it), mappings not working in tsx files, probably because of precendece issues
  (map! :map smerge-mode-map :prefix "]" :desc "Jump to next conflict" :m "g" #'smerge-vc-next-conflict)
  (map! :map smerge-mode-map :prefix "[" :desc "Jump to prev conflict" :m "g" #'smerge-prev))
