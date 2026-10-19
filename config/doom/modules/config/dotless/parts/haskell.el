;;; parts/haskell.el -*- lexical-binding: t; -*-

(add-hook! haskell-mode
  (set-fill-column 100))

(add-hook! haskell-literate-mode 'lsp)
(after! haskell
  (defun zz/easy-import-haskell-symbol ()
    "A hacky way to help add import for the thing at point in Haskell."
    (interactive)
    (let ((the-word (current-word)))
      (goto-char 0)
      (search-forward "module")
      (search-forward "import")
      (+haskell/evil-open-above)
      (save-excursion
        (insert (format "import  (%s)" the-word)))
      (search-forward "import")
      (evil-append 1)))
  (defun zz/load-haskell-compilation-error-regexp-alist ()
    "`haskell-mode' exposes `haskell-compile' as an alternative to `compile'
with regexes that allow linking errors to source files in the compilation
buffer. However, when using it, sometimes behave weirdly, here we copy those
regexes to the variables used by `compile' so that we are able to just use that
and have file links work."
    (let* ((idx 0)
           (regex-key (intern (format "haskell-error-%d" idx))))
      (dolist (regex haskell-compilation-error-regexp-alist)
        (unless (assoc regex-key compilation-error-regexp-alist-alist)
          (add-to-list 'compilation-error-regexp-alist-alist (cons regex-key regex)))
        (add-to-list 'compilation-error-regexp-alist regex-key)
        (setq idx (1+ idx)))))
  (zz/load-haskell-compilation-error-regexp-alist)
  (setopt haskell-indentation-layout-offset 4
         haskell-indentation-starter-offset 4
         haskell-indentation-left-offset 4
         haskell-indentation-where-pre-offset -2
         haskell-indentation-where-post-offset 0
         haskell-hoogle-port-number 8123
         haskell-hoogle-url (format "http://localhost:%d/?hoogle=%%s" haskell-hoogle-port-number)
         ;; NOTE we could not set `haskell-hoogle-server-command' because we
         ;;   manage hoogle via a systemd service, but in the event Emacs tries
         ;;   to start an instance, then we just ignore the port (it should be
         ;;   whatever `haskell-hoogle-port-number' is set to, and then just
         ;;   start the hoogle service
         haskell-hoogle-server-command #'(lambda (_port) "systemctl --user start hoogle.service"))
  (map! :mode haskell :map haskell-mode-map :leader :prefix "c" :desc "Compile" :nv "c" #'haskell-compile)
  (map! :mode haskell :map haskell-cabal-mode-map :leader :prefix "c" :desc "Compile" :nv "c" #'haskell-compile)
  (map! :mode haskell :map haskell-mode-map :leader :prefix "c" :desc "Add type signature" :n "T"  #'zz/lsp-haskell-add-type-signature)
  (map! :mode haskell :map haskell-mode-map :localleader :desc "Search Hoogle" :nv "s" #'consult-hoogle)
  (map! :mode haskell :map haskell-mode-map :localleader :desc "Go to imports" :n "i" #'haskell-navigate-imports)
  (map! :mode haskell :map haskell-mode-map :localleader :desc "Easy import symbol" :n "I" #'zz/easy-import-haskell-symbol)
  (map! :mode haskell :map haskell-mode-map :localleader :desc "Describe thing at point" :n "d" #'lsp-describe-thing-at-point)
  (map! :mode haskell :map haskell-mode-map :localleader :desc "Add type signature" :n "T"  #'zz/lsp-haskell-add-type-signature)
  (map! :mode haskell :map haskell-mode-map :localleader :prefix "h" :desc "Hoogle buffer" :n "s" #'hoogle-buffer)
  (map! :mode haskell :map haskell-mode-map :localleader :prefix "h" :desc "Hoogle search web" :n "o" #'haskell-hoogle-lookup-from-website)
  (map! :mode haskell :map haskell-mode-map :localleader :prefix "h" :desc "Hoogle search local" :n "l" #'haskell-hoogle-lookup-from-local)
  (map! :mode haskell :map haskell-mode-map :localleader :prefix "h" :desc "Toggle forms visibility" :n "t" #'haskell-hide-toggle)
  (map! :mode haskell :map haskell-mode-map :localleader :prefix "h" :desc "Toggle all forms visibility" :n "T" #'haskell-hide-toggle-all))

(after! lsp-haskell
  (defun zz/lsp-get-type-signature (lang str)
    "Get LANGs type signature in STR.
Original implementation from https://github.com/emacs-lsp/lsp-mode/pull/1740."
    (let* ((start (concat "```" lang))
           (groups (--filter (s-equals? start (car it))
                             (-partition-by #'s-blank? (s-lines (s-trim str)))))
           (name-at-point (symbol-name (symbol-at-point)))
           (type-sig-group (car
                            (--filter (s-contains? name-at-point (cadr it))
                                      groups))))
      (->> (or type-sig-group (car groups))
           (-drop 1)                    ; ``` LANG
           (-drop-last 1)               ; ```
           (-map #'s-trim)
           (s-join " "))))
  (defun zz/lsp-get-type-signature-at-point (&optional lang)
    "Get LANGs type signature at point.
LANG is not given, get it from `lsp--buffer-language'."
    (interactive)
    (-some->> (lsp--text-document-position-params)
      (lsp--make-request "textDocument/hover")
      lsp--send-request
      lsp:hover-contents
      (funcall (-flip #'plist-get) :value)
      (zz/lsp-get-type-signature (or lang lsp--buffer-language))))
  (defun zz/lsp-haskell-add-type-signature ()
    "Add a type signature for the thing at point.
This is very convenient, for example, when dealing with local
functions, since those—as opposed to top-level expressions—don't
have a code lens for \"add type signature here\" associated with
them."
    (interactive)
    (let* ((value (zz/lsp-get-type-signature-at-point "haskell")))
      (back-to-indentation)
      (insert value)
      (haskell-indentation-newline-and-indent)))

  ;; This is re-set after LSP loads because otherwise LSP re-writes it to 1MiB
  (setopt read-process-output-max (* 2 1024 1024) ; 2MiB goes hand-in-hand with "sysctl fs.pipe-max-size"
          lsp-haskell-server-path "haskell-language-server-wrapper"
          lsp-lens-enable nil
          lsp-enable-suggest-server-download nil
          lsp-headerline-breadcrumb-enable nil
          lsp-haskell-session-loading "multipleComponents"
          lsp-haskell-plugin-stan-global-on nil
          lsp-haskell-check-project nil
          lsp-enable-file-watchers nil
          lsp-haskell-formatting-provider "fourmolu"
          lsp-haskell-max-completions 10
          lsp-haskell-check-parents "CheckOnSave"))
