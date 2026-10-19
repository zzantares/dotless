;;; ztd.el --- ZzAntares' Standard Library -*- lexical-binding: t; -*-

;; Copyright (C) 2025  Julio César

;; Author: Julio César <zzantares@gmail.com>
;; Keywords: lisp, convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This is a supporting library which defines general enough functions that may
;; come useful in diverse situations when writing some Emacs code to do
;; something.

;;; Code:

(require 'dash)
(require 'auth-source)

;; TODO rename prefix 'zz/' -> 'ztd-'
(defun zz/file-exists-p (filepath)
  "Determine if a given file exists returning the FILEPATH if it does."
  (when (file-exists-p filepath)
    filepath))

(defun zz/is-haskell-package-p (dir)
  "Determine if the given DIR is a haskell package directory.
Returns the full path to the detected Haskell package file."
  (let ((hs-files '("package.yaml" "*.cabal" "cabal.project" "stack.yaml")))
    (-any (lambda (x)
            (or (zz/file-exists-p (concat dir x))
                (-any 'zz/file-exists-p (file-expand-wildcards (concat dir x)))))
          hs-files)))

(defun zz/is-clojure-package-p (dir)
  "Determine if the given directory is a clojure project directory.
Returns the full path to the detected Clojure project file.
Argument DIR This is me trying out stuff."
  (let ((clj-files '("project.clj")))
    (-any (lambda (x)
            (or (zz/file-exists-p (concat dir x))
                (-any 'zz/file-exists-p (file-expand-wildcards (concat dir x)))))
          clj-files)))

(defun zz/is-nix-package-p (dir)
  "Determine if the given directory is a nix project directory.
Returns the full path to the detected Nix flake file.
Argument DIR This is me trying out stuff."
  (let ((nix-files '("flake.nix" "flake.lock" "shell.nix")))
    (-any (lambda (x)
            (or (zz/file-exists-p (concat dir x))
                (-any 'zz/file-exists-p (file-expand-wildcards (concat dir x)))))
          nix-files)))

(defun zz/is-package-dir (dir)
  "Determine if the given DIR refers to a package.
Returns the full path to the detected package file.
Useful to use when `locate-dominating-file'."
  ;; TODO Should be refactored so we have a mapping from 'major-mode -> package-file-list'
  (cond ((derived-mode-p 'haskell-mode 'haskell-cabal-mode) (zz/is-haskell-package-p dir))
        ((derived-mode-p 'clojure-mode) (zz/is-clojure-package-p dir))
        ((derived-mode-p 'nix-mode) (zz/is-nix-package-p dir))
        (t (message (concat "Finding package for " (symbol-name major-mode) " is not supported!"))
           nil)))

(defun zz/auth-info-key (the-login the-host)
  "Read a password from the auth-source facilities.
THE-LOGIN is matched against the :login value whereas
THE-HOST is matched against :host properties of the authinfo entry."
  (when-let ((found (auth-source-search :max 1 :type 'netrc :login the-login :host the-host)))
    (auth-info-password (car found))))

(provide 'ztd)

;;; ztd.el ends here
