;; -*- no-byte-compile: t; -*-
;;; config/dotless/packages.el

;;; Utilities
(package! nov)
(package! djvu)
(package! ement)
(package! agitjo)
(package! disable-mouse)
(package! drag-stuff)
(package! linear-emacs
  :recipe (:host github :repo "anegg0/linear-emacs"))
(package! lsp-biome
  :recipe (:host github :repo "cxa/lsp-biome"))
(package! claude-code-ide
  :recipe (:host github :repo "manzaltu/claude-code-ide.el"))
(package! vterm :built-in t)            ; made available by Nix
(package! kiwix :built-in t)            ; made available by Nix
(package! vterm-anti-flicker-filter
  :recipe (:host github :repo "martinbaillie/vterm-anti-flicker-filter"))

(package! consult-hoogle
  :recipe (:host codeberg :repo "rahguzar/consult-hoogle"))

;;; Language support packages
(package! ssh-config-mode)
(package! just-mode)
(package! adoc-mode)
(package! vimrc-mode)

;; Language related utilities
(package! kaocha-runner)

;;; Org enhancements
(package! ox-gfm)
(package! ob-mermaid)
(package! engrave-faces)

;;; Theme packages
(package! ef-themes)
(package! tao-theme)
(package! poet-theme)
(package! acme-theme)
(package! jazz-theme)
(package! nimbus-theme)
(package! flatui-theme)
(package! modus-themes)
(package! doric-themes)
(package! kaolin-themes)
(package! nezburn-theme)
(package! flexoki-themes)
(package! solo-jazz-theme)
(package! hc-zenburn-theme)
(package! catppuccin-theme)
(package! tango-plus-theme)
(package! almost-mono-themes)
(package! anti-zenburn-theme)
(package! nordic-night-theme)
(package! twilight-bright-theme)

;; Fork that fixes fringe diffs; see
;; https://github.com/purcell/color-theme-sanityinc-tomorrow/pull/177
;; Declared only where the checkout exists, so `doom sync' works without it.
(when (file-directory-p "~/workspace/emacs/color-theme-sanityinc-tomorrow")
  (package! color-theme-sanityinc-tomorrow
    :recipe (:local-repo "~/workspace/emacs/color-theme-sanityinc-tomorrow")))
