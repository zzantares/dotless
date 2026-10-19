;;; parts/kiwix.el -*- lexical-binding: t; -*-

;; Offline documentation through the local kiwix-serve (dotless
;; nixosModules.kiwix). Results render in eww so lookups stay in Emacs, and
;; read the same pinned ZIMs the browser does - devdocs.el cannot read ZIM at
;; all, so using it would mean a second copy of every docset.
(after! kiwix
  (setq kiwix-server-type 'kiwix-serve-local
        kiwix-server-url "http://127.0.0.1"
        kiwix-server-port 8124
        ;; kiwix.el builds its library menu from the *.zim names here
        kiwix-zim-dir "/var/lib/kiwix/zims"
        kiwix-default-browser-function #'eww-browse-url))
