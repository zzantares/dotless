;;; parts/apheleia.el -*- lexical-binding: t; -*-

(after! apheleia
  (add-to-list 'apheleia-formatters '(dhall-format "dhall" "format"))
  (add-to-list 'apheleia-formatters '(cabal-fmt "cabal-fmt"))
  (add-to-list 'apheleia-mode-alist '(dhall-mode . dhall-format))
  (add-to-list 'apheleia-mode-alist '(haskell-cabal-mode . cabal-fmt))
  (setf (alist-get 'fourmolu apheleia-formatters)
      '("fourmolu"
        "--ghc-opt" "-XImportQualifiedPost"
        "--ghc-opt" "-XBangPatterns"
        "--stdin-input-file" filepath)))

(setq-hook! 'typescript-mode-hook +format-with 'biome)
