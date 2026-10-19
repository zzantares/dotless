;;; parts/lsp.el -*- lexical-binding: t; -*-

(setopt lsp-warn-no-matched-clients nil)
(after! lsp
  (setopt lsp-use-plists t
         lsp-organize-imports t)
  ;; (setopt lsp-ui-doc-enable nil)
  ;; (setopt lsp-ui-sideline-enable nil)
  (add-to-list 'lsp-file-watch-ignored-directories "[/\\\\]ghc")
  (add-to-list 'lsp-language-id-configuration '(sh-mode . "bash-language-server")))

(after! lsp-nix
  (setopt lsp-nix-nil-auto-eval-inputs nil))

(after! lsp-biome
  (setopt lsp-biome-format-on-save t
         lsp-biome-organize-imports-on-save t))
(after! lua-mode
  (setopt lsp-clients-lua-language-server-bin (executable-find "lua-language-server")))
