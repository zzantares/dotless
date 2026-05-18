;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el

;; To install a package with Doom you must declare them here and run 'doom sync'
;; on the command line, then restart Emacs for the changes to take effect -- or
;; use 'M-x doom/reload'.


;; To install SOME-PACKAGE from MELPA, ELPA or emacsmirror:
                                        ;(package! some-package)

;; To install a package directly from a remote git repo, you must specify a
;; `:recipe'. You'll find documentation on what `:recipe' accepts here:
;; https://github.com/radian-software/straight.el#the-recipe-format
                                        ;(package! another-package
                                        ;  :recipe (:host github :repo "username/repo"))

;; If the package you are trying to install does not contain a PACKAGENAME.el
;; file, or is located in a subdirectory of the repo, you'll need to specify
;; `:files' in the `:recipe':
                                        ;(package! this-package
                                        ;  :recipe (:host github :repo "username/repo"
                                        ;           :files ("some-file.el" "src/lisp/*.el")))

;; If you'd like to disable a package included with Doom, you can do so here
;; with the `:disable' property:
                                        ;(package! builtin-package :disable t)

;; You can override the recipe of a built in package without having to specify
;; all the properties for `:recipe'. These will inherit the rest of its recipe
;; from Doom or MELPA/ELPA/Emacsmirror:
                                        ;(package! builtin-package :recipe (:nonrecursive t))
                                        ;(package! builtin-package-2 :recipe (:repo "myfork/package"))

;; Specify a `:branch' to install a package from a particular branch or tag.
;; This is required for some packages whose default branch isn't 'master' (which
;; our package manager can't deal with; see radian-software/straight.el#279)
                                        ;(package! builtin-package :recipe (:branch "develop"))

;; Use `:pin' to specify a particular commit to install.
                                        ;(package! builtin-package :pin "1a2b3c4d5e")

;; Doom's packages are pinned to a specific commit and updated from release to
;; release. The `unpin!' macro allows you to unpin single packages...
                                        ;(unpin! pinned-package)
;; ...or multiple packages
                                        ;(unpin! pinned-package another-pinned-package)
;; ...Or *all* packages (NOT RECOMMENDED; will likely break things)
                                        ;(unpin! t)

;;; Utilities
(package! nov)
(package! djvu)
(package! ement)
(package! disable-mouse)
(package! drag-stuff)
(package! linear-emacs
  :recipe (:host github :repo "anegg0/linear-emacs"))
(package! lsp-biome
  :recipe (:host github :repo "cxa/lsp-biome"))
(package! claude-code-ide
  :recipe (:host github :repo "manzaltu/claude-code-ide.el"))
(package! vterm :built-in t)            ; made available by Nix
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

;; We use our own fork of this theme colection to address diffs in the fringe issues
;; See: https://github.com/purcell/color-theme-sanityinc-tomorrow/pull/177
(package! color-theme-sanityinc-tomorrow
  :recipe (:local-repo "~/workspace/emacs/color-theme-sanityinc-tomorrow"))
