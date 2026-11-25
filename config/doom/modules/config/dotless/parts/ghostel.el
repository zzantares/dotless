;;; parts/ghostel.el -*- lexical-binding: t; -*-

;; Only claude-code-ide runs on this backend; Doom's :term module keeps vterm.
(after! ghostel
  ;; Nix ships ghostel-module.so in the package dir, which is also where the
  ;; download would land - read-only. Report it missing instead of offering one.
  (setopt ghostel-module-auto-install nil)

  ;; The 5 MB default is ~5000 rows at 80 columns, fewer in a 90-column side
  ;; window. A long Claude session outruns it.
  (setopt ghostel-max-scrollback (* 20 1024 1024)))

;; Terminal-aware evil operators, plus the anchor inhibit that lets normal state
;; roam off the live cursor instead of snapping back on every redraw.
(add-hook 'ghostel-mode-hook #'evil-ghostel-mode)
