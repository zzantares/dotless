;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-
;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!

(setq system-time-locale "C"            ;; Makes sure English weekdays and timestamps are in English
      custom-file (concat (file-name-as-directory doom-user-dir)
                          (format "modules/config/%s/custom.el" user-login-name)))
(load custom-file)

;; Include custom lisp code files
(add-load-path! "lisp/")
(require 'ztd)
(require 'zutil)                        ; TODO Replace with *-extra Doom Modules?

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-unicode-font' -- for unicode glyphs
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
(setq doom-font (font-spec :family "CaskaydiaCove Nerd Font" :size 12.0 :weight 'normal)
      doom-big-font (font-spec :family "CaskaydiaCove Nerd Font" :size 18.0 :weight 'normal)
      doom-variable-pitch-font (font-spec :family "CaskaydiaCove Nerd Font" :size 14.0))
;;
;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type 'relative)
(remove-hook! 'text-mode-hook #'display-line-numbers-mode)
(remove-hook! 'vterm-mode-hook #'display-line-numbers-mode)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/Documents/org/")
(setq org-agenda-files '("~/Documents/org/agenda.org" "~/Documents/org/todo.org"))
(setq +org-capture-journal-file (concat +org-capture-journal-file ".gpg"))

;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `after!' block, otherwise Doom's defaults may override your settings. E.g.
;;
;;   (after! PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; If having trouble binding keys be sure to read:
;; https://www.gnu.org/software/emacs/manual/html_node/elisp/Functions-for-Key-Lookup.html
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

(setq auth-sources
      (list (concat (file-name-as-directory (getenv "DOTFILES_FLAKE_ROOT"))
                    (format "secrets/%s/.authinfo.gpg" user-login-name))))
(setq ispell-dictionary "en")
(setq-default line-spacing 3
              indent-tabs-mode nil
              tab-width 4)

(setq +format-on-save-disabled-modes
      '(not
        emacs-lisp-mode                 ; lispy does formatting
        tex-mode                        ; latexindent is broken
        latex-mode
        jinja2-mode                     ; prettier treats it as HTML and it mungles Ansible templates e.g. systemd units templates
        yaml-mode))

(setopt world-clock-list
       '(("UTC" "UTC")
         ("America/Chicago" "Chicago")
         ("America/Los_Angeles" "Los Angeles")
         ("America/New_York" "New York")
         ("Asia/Tokyo" "Tokyo")
         ("Europe/London" "London")
         ("America/Cancun" "Cancun")
         ("America/Mexico_City" "Mexico City")))

;; As the name implies this is a list of packages to be loaded incrementally
(doom-load-packages-incrementally '(claude-code-ide gptel))

;; TODO This works for compilation mode but breaks vterm (it doesn't load oh-my-zsh)
;;      there was a way to only make this as an advice to compilation mode
;; (setenv "ZDOTDIR" (concat doom-user-dir "env")) ; make emacs load zsh aliases

(after! notmuch
  (defun zz/notmuch-browser-view ()
    "Open the text/html part of the current message using `notmuch-show-view-part'."
    (interactive)
    (when (string= (shr-browse-url) "No link under point")
      (save-excursion
        (goto-char
         (prop-match-beginning
          (text-property-search-forward
           :notmuch-part "text/html"
           (lambda (value notmuch-part)
             (equal (plist-get notmuch-part :content-type)
                    value)))))
        (notmuch-show-view-part))))
  (setq +notmuch-sync-backend 'mbsync)
  (set-popup-rule! "^\\*notmuch-hello" :ignore t)
  (setq notmuch-tagging-keys
        '(("a" notmuch-archive-tags "Archive")
          ("r" notmuch-show-mark-read-tags "Mark Read")
          ("u" ("+unread" "+inbox") "Mark as Unread")
          ("f" ("+flagged") "Flag")
          ("s" ("+spam" "-inbox") "Mark as Spam")
          ("d" ("+deleted" "-inbox") "Delete")))
  (map! :map notmuch-hello-mode-map :nv "l" #'widget-forward)
  (map! :map notmuch-hello-mode-map :nv "j" #'widget-backward)
  (map! :map notmuch-hello-mode-map :nv "l" #'evil-next-line)
  (map! :map notmuch-hello-mode-map :nv "j" #'evil-previous-line)
  (map! :map notmuch-hello-mode-map :nv "?" #'notmuch-help)
  (map! :map notmuch-hello-mode-map :nv "o" #'evil-collection-notmuch-hello-ret)
  (map! :map notmuch-search-mode-map :localleader :g "t" #'notmuch-tag-jump)
  (map! :map notmuch-search-mode-map :nv "o" #'notmuch-search-show-thread)
  (map! :map notmuch-search-mode-map :nv "r" #'notmuch-search-toggle-order)
  (map! :map notmuch-show-mode-map :nv "?" #'notmuch-help)
  (map! :map notmuch-show-mode-map :localleader :g "t" #'notmuch-tag-jump)
  (map! :map notmuch-show-mode-map :nv "o" #'zz/notmuch-browser-view))

(after! message
  (setq message-kill-buffer-on-exit t))

(after! org-mime
  (setq org-mime-export-options
        '(:section-numbers nil
          :with-author nil
          :with-toc nil)))

(setopt evil-snipe-scope 'visible)

(after! evil
  (defun zz/scroll-line-to-quarter ()
    "Scrolls windows so that the current line ends at roughly ~25% of the window."
    (interactive)
    (evil-scroll-line-to-top (- (line-number-at-pos) 13))
    (evil-next-visual-line 13))

  (map! :nv "h" #'evil-previous-line)
  (map! :nv "k" #'evil-next-line)
  (map! :nv "j" #'evil-backward-char)
  (map! :nv "l" #'evil-forward-char)
  (map! :prefix "g" :nv "b" #'evil-buffer)
  (map! :m "j" #'evil-backward-char)
  (map! :m "l" #'evil-forward-char)
  (map! :m "k" #'evil-next-line)
  (map! :m "h" #'evil-previous-line)
  (map! :g "M-h" #'drag-stuff-up)
  (map! :g "M-k" #'drag-stuff-down)
  (map! :g "M-K" #'kill-sentence)
  (map! :g "M-H" #'mark-paragraph)
  (map! :v "v" #'er/expand-region)
  (map! :v "V" #'er/contract-region)
  (map! :prefix "g" :m "o" (lambda ()
                               (interactive)
                               (let ((current-prefix-arg 1))
                                 (call-interactively #'evil-avy-goto-char-2))))
  (map! :prefix "g" :m "/" (lambda ()
                               (interactive)
                               (let ((current-prefix-arg 1))
                                 (call-interactively #'evil-avy-goto-char-timer))))
  (map! :prefix "C-x" :gi "C-l" :desc "Complete next line" #'evil-complete-previous-line)
  (map! :prefix "C-x" :gi "C-p" :desc "Complete nearest preceding word" #'evil-complete-previous)
  (map! :prefix "C-x" :gi "C-n" :desc "Complete nearest next word" #'evil-complete-next)
  (map! :prefix "C-x" :gi "M-l" :desc "Company next line" #'+company/whole-lines)
  (map! :prefix "z" :nv "v" #'zz/scroll-line-to-quarter)
  (map! :leader :prefix "w" :desc "Delete other windows" :nv "O" #'delete-other-windows)
  (map! :leader :prefix "w" :desc "Maximize this window" :nv "o" #'doom/window-maximize-buffer)
  (map! :leader :prefix "w" :desc "Enlarge the current window" :nv "e" #'doom/window-enlargen)
  (map! :leader :prefix "w" :desc "Maximize window horizontally" :nv "S" #'doom/window-maximize-horizontally)
  (map! :leader :prefix "w" :desc "Maximize window vertically" :nv "V" #'doom/window-maximize-vertically)
  (map! :leader :prefix "o" :desc "Open psql client repl" :nv "P" #'sql-postgres)
  (map! :prefix "C-w" :nv "O" #'delete-other-windows)
  (map! :prefix "C-w" :nv "o" #'doom/window-maximize-buffer)
  (map! :prefix "C-w" :nv "u" #'winner-undo)
  (map! :prefix "C-w" :nv "e" #'doom/window-enlargen)
  (map! :prefix "C-w" :nv "s" #'+evil/window-split-and-follow)
  (map! :prefix "C-w" :nv "v" #'+evil/window-vsplit-and-follow)
  (map! :prefix "C-w" :nv "S" #'doom/window-maximize-horizontally)
  (map! :prefix "C-w" :nv "V" #'doom/window-maximize-vertically)
  (map! :prefix "C-w" :nv "h" #'evil-window-up)
  (map! :prefix "C-w" :nv "k" #'evil-window-down)
  (map! :prefix "C-w" :nv "j" #'evil-window-left)
  (map! :prefix "C-w" :nv "l" #'evil-window-right)
  (map! :prefix "C-w" :nv "H" #'+evil/window-move-up)
  (map! :prefix "C-w" :nv "K" #'+evil/window-move-down)
  (map! :prefix "C-w" :nv "J" #'+evil/window-move-left)
  (map! :prefix "C-w" :nv "L" #'+evil/window-move-right)
  (map! :prefix "C-w" :nv "C-h" #'evil-window-up)
  (map! :prefix "C-w" :nv "C-k" #'evil-window-down)
  (map! :prefix "C-w" :nv "C-j" #'evil-window-left)
  (map! :prefix "C-w" :nv "C-l" #'evil-window-right)
  (map! :prefix "C-w" :nv "C-S-h" #'evil-window-move-very-top)
  (map! :prefix "C-w" :nv "C-S-k" #'evil-window-move-very-bottom)
  (map! :prefix "C-w" :nv "C-S-j" #'evil-window-move-far-left)
  (map! :prefix "C-w" :nv "C-S-l" #'evil-window-move-far-right)
  (map! :prefix "C-t" :desc "New workspace" :nv "c" #'+workspace/new)
  (map! :prefix "C-t" :desc "Delete workspace" :nv "x" #'+workspace/kill)
  (map! :prefix "C-t" :desc "Next workspace" :nv "n" #'+workspace/switch-right)
  (map! :prefix "C-t" :desc "Previous workspace" :nv "p" #'+workspace/switch-left)
  (map! :prefix "C-t" :desc "Switch to workspace" :nv "T" #'+workspace/switch-to)
  (map! :prefix "C-t" :desc "Switch to workspace" :nv "t" #'+workspace/other)
  (map! :prefix "g" :desc "Switch to other workspace" :nv "t" #'+workspace/other)
  (map! :prefix "C-t" :desc "Load workspace from file" :nv "L" #'+workspace/load)
  (map! :prefix "C-t" :desc "List workspaces" :nv "l" #'+workspace/switch-to)
  (map! :prefix "C-t" :desc "List workspaces" :nv "R" #'+workspace/restore-last-session)
  (map! :prefix "C-t" :desc "Rename workspace" :nv "r" #'+workspace/rename)
  (map! :prefix "C-t" :desc "Rename workspace" :nv "," #'+workspace/rename)
  (map! :prefix "C-t" :desc "New workspace" :nv "C-c" #'+workspace/new)
  (map! :prefix "C-t" :desc "Delete workspace" :nv "C-x" #'+workspace/kill)
  (map! :prefix "C-t" :desc "Next workspace" :nv "C-n" #'+workspace/switch-right)
  (map! :prefix "C-t" :desc "Previous workspace" :nv "C-p" #'+workspace/switch-left)
  (map! :prefix "C-t" :desc "Switch to other workspace" :nv "C-t" #'+workspace/other)
  (map! :prefix "C-t" :desc "Load workspace from file" :nv "C-L" #'+workspace/load)
  (map! :prefix "C-t" :desc "List workspaces" :nv "C-l" #'+workspace/switch-to)
  (map! :prefix "C-t" :desc "List workspaces" :nv "C-R" #'+workspace/restore-last-session)
  (map! :prefix "C-t" :desc "Rename workspace" :nv "C-r" #'+workspace/rename)
  (map! :prefix "C-t" :desc "Rename workspace" :nv "C-," #'+workspace/rename)
  (map! :prefix "C-t" :desc "Switch to 1st workspace" :nv "1" #'+workspace/switch-to-0)
  (map! :prefix "C-t" :desc "Switch to 2nd workspace" :nv "2" #'+workspace/switch-to-1)
  (map! :prefix "C-t" :desc "Switch to 3rd workspace" :nv "3" #'+workspace/switch-to-2)
  (map! :prefix "C-t" :desc "Switch to 4th workspace" :nv "4" #'+workspace/switch-to-3)
  (map! :prefix "C-t" :desc "Switch to 5th workspace" :nv "5" #'+workspace/switch-to-4)
  (map! :prefix "C-t" :desc "Switch to 6th workspace" :nv "6" #'+workspace/switch-to-5)
  (map! :prefix "C-t" :desc "Switch to 7th workspace" :nv "7" #'+workspace/switch-to-6)
  (map! :prefix "C-t" :desc "Switch to 8th workspace" :nv "8" #'+workspace/switch-to-7)
  (map! :prefix "C-t" :desc "Switch to 9th workspace" :nv "9" #'+workspace/switch-to-8)
  (map! :prefix "C-t" :desc "Switch to final workspace" :nv "0" #'+workspace/switch-to-final)
  (map! :map doom-leader-workspace-map :leader :prefix "TAB" :desc "New workspace" :nv "c" #'+workspace/new)
  (map! :map doom-leader-workspace-map :leader :prefix "TAB" :desc "Delete workspace" :nv "x" #'+workspace/kill)
  (map! :map doom-leader-workspace-map :leader :prefix "TAB" :desc "Next workspace" :nv "n" #'+workspace/switch-right)
  (map! :map doom-leader-workspace-map :leader :prefix "TAB" :desc "Previous workspace" :nv "p" #'+workspace/switch-left)
  (map! :map doom-leader-workspace-map :leader :prefix "TAB" :desc "Load workspace from file" :nv "L" #'+workspace/load)
  (map! :map doom-leader-workspace-map :leader :prefix "TAB" :desc "List workspaces" :nv "l" #'+workspace/switch-to)
  (map! :map doom-leader-workspace-map :leader :prefix "TAB" :desc "Rename workspace" :nv "," #'+workspace/rename)
  (map! :map messages-buffer-mode-map :nv "q" #'evil-force-normal-state)
  (map! :leader :prefix "l" :desc "Claude Code" :nv "c" #'claude-code-ide-menu)
  (map! :leader :prefix "o" (:prefix "a" :desc "Open agenda file" :m "f" #'org-cycle-agenda-files)))

(after! dired
  (map! :leader :prefix "t" :desc "Dired at this location" :nv "t" #'dired-jump)
  (map! :mode dired :map dired-mode-map :n "k" #'dired-next-line)
  (map! :mode dired :map dired-mode-map :n "h" #'dired-previous-line)
  (map! :mode dired :map dired-mode-map :n "o" #'dired-find-file)
  (map! :mode dired :map dired-mode-map :n "u" #'dired-up-directory))

(after! (:and dired persp-mode)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "New workspace" :n "c" #'+workspace/new)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "Delete workspace" :n "x" #'+workspace/kill)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "Switch to other workspace" :nv "t" #'+workspace/other)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "Switch to workspace" :nv "T" #'+workspace/switch-to)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "New workspace" :n "C-c" #'+workspace/new)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "Delete workspace" :n "C-x" #'+workspace/kill)
  (map! :mode dired :map dired-mode-map :prefix "C-t" :desc "Switch to other workspace" :nv "C-t" #'+workspace/other))

(after! dirvish
  (map! :map dirvish-mode-map :n "k" #'dired-next-line)
  (map! :map dirvish-mode-map :n "h" #'dired-previous-line)
  (map! :map dirvish-mode-map :n "o" #'dired-find-file)
  (map! :map dirvish-mode-map :n "u" #'dired-up-directory))

(after! flycheck
  (map! :prefix "]" :desc "Next error" :m "e" #'flycheck-next-error)
  (map! :prefix "[" :desc "Next error" :m "e" #'flycheck-previous-error))

(add-hook! '(treemacs-mode-hook evil-treemacs-state-entry-hook) #'hide-mode-line-mode)

(after! treemacs-evil
  (setopt treemacs-width 40)
  (evil-define-key 'treemacs treemacs-mode-map (kbd "h") #'treemacs-previous-line)
  (map! :map (treemacs-mode-map evil-treemacs-state-map)
        "k" #'treemacs-next-line
        "h" #'treemacs-previous-line
        "l" #'treemacs-RET-action
        "j" #'treemacs-COLLAPSE-action
        "M-k" #'treemacs-next-neighbour
        "M-h" #'treemacs-previous-neighbour
        "M-J" #'treemacs-root-up
        "M-L" #'treemacs-root-down
        "M-K" #'treemacs-next-line-other-window
        "M-H" #'treemacs-previous-line-other-window))

;; Make the workspace name match the project name
;; TODO either persp-mode broke with the update or this is wrong, it causes workspace to have the wrong names (they shift)
;;   consider triggering only if current workspace name is "main" (the default name)
;; (add-hook! 'persp-activated-functions
;;   (when (projectile-project-p)
;;     (let ((inhibit-message t))
;;       (+workspace/rename (projectile-project-name)))))

(after! projectile
  (defun zz/projectile-package-dir ()
    "Open closest package directory found upwards starting from `default-directory'."
    (interactive)
    (let ((package-dir (projectile-locate-dominating-file default-directory #'zz/is-package-dir)))
      (when package-dir (dired package-dir))))
  (defun zz/projectile-package-file ()
    "Open closest package file found upwards starting from `default-directory'."
    (interactive)
    (let ((package-dir (projectile-locate-dominating-file default-directory #'zz/is-package-dir)))
      (when package-dir
        (find-file (zz/is-package-dir package-dir)))))
  ;; store projectile projects outside of ~/.config/emacs/.local since we re-install emacs often and we loose it
  ;; TODO we could instead make the upgrade recipe to temporarily backup  ~/.config/emacs/.local/cache/projectile/projects.eld
  (setopt projectile-known-projects-file
          (expand-file-name "doom/projectile-projects.eld"
                            (or (getenv "XDG_DATA_HOME") "~/.local/share")))
  (map! :leader :prefix "t" :desc "Dired at project root" :nv "r" #'projectile-dired)
  (map! :leader :prefix "t" :desc "Dired at package root" :nv "p" #'zz/projectile-package-dir)
  (map! :map projectile-command-map :leader :prefix "p" :desc "Kill ongoing compilation" :nv "K" #'kill-compilation)
  (map! :nv "C-p" #'projectile-find-file)
  (map! :localleader :desc "Package description file" :nv "," #'zz/projectile-package-file))

(after! simple
  (map! :map special-mode-map :desc "Quit" :nv "q" #'quit-window))

(after! forge
  ;; store forge database outside of ~/.config/emacs/.local since we re-install emacs often and we loose it
  ;; TODO we could instea dmake the upgrade recipe to temporarily backup ~/.config/emacs/.local/etc/forge/forge-database.sqlite
  (setopt forge-database-file
         (expand-file-name "doom/forge-database.sqlite"
                           (or (getenv "XDG_DATA_HOME") "~/.local/share")))
  (add-to-list 'forge-alist '("gitlab.haskell.org" "gitlab.haskell.org/api/v4" "gitlab.haskell.org" forge-gitlab-repository)))

(after! magit
  (setopt magit-log-section-commit-count 20)
  (setf (alist-get 'unpushed magit-section-initial-visibility-alist) 'show) ;; auto-expand recent commits section
  ;; TODO theres a new undocumented filtering mechanism that replaces the section hooks see: https://github.com/magit/forge/issues/676
  ;; (magit-add-section-hook 'magit-status-sections-hook #'forge-insert-requested-reviews 'forge-insert-pullreqs nil)
  ;; (magit-add-section-hook 'magit-status-sections-hook #'forge-insert-assigned-pullreqs 'forge-insert-pullreqs nil)
  ;; (magit-add-section-hook 'magit-status-sections-hook #'forge-insert-assigned-issues 'forge-insert-pullreqs)
  ;; (magit-add-section-hook 'magit-status-sections-hook #'forge-insert-authored-issues 'forge-insert-issues nil)
  ;; TODO This setting doesn't look right because of line height images look odd
  (setq magit-revision-show-gravatars '("^Author:     " . "^Commit:     "))
  (map! :map magit-mode-map "C-t" nil)  ; pass-through to global map
  (map! :map magit-mode-map :nv "k" #'evil-next-visual-line)
  (map! :map magit-mode-map :nv "h" #'evil-previous-visual-line)
  (map! :map magit-mode-map :nv "n" #'magit-section-forward)
  (map! :map magit-mode-map :nv "p" #'magit-section-backward)
  (map! :map magit-mode-map :nv "C-n" #'magit-section-forward)
  (map! :map magit-mode-map :nv "C-p" #'magit-section-backward)
  (map! :map magit-mode-map :nv "C-k" #'magit-section-forward)
  (map! :map magit-mode-map :nv "C-h" #'magit-section-backward)
  (map! :map magit-mode-map :prefix "C-w" :nv "k" #'evil-window-down)
  (map! :map magit-mode-map :prefix "C-w" :nv "h" #'evil-window-up)
  (map! :map magit-mode-map :prefix "C-w" :nv "j" #'evil-window-left)
  (map! :map magit-mode-map :prefix "C-w" :nv "l" #'evil-window-right)
  (map! :map magit-mode-map :localleader :m "h" #'magit-smerge-keep-upper)
  (map! :map magit-mode-map :localleader :m "k" #'magit-smerge-keep-lower)
  (map! :map magit-mode-map :localleader :m "a" #'magit-smerge-keep-all)
  (map! :map magit-mode-map :localleader :m "n" #'magit-smerge-keep-base)
  (map! :map magit-mode-map :localleader :m "g" #'magit-smerge-keep-current)
  ;; TODO These workspace bindings are basically duplicated, need to fix that
  (map! :map magit-mode-map :prefix "C-t" :desc "New workspace" :nv "c" #'+workspace/new)
  (map! :map magit-mode-map :prefix "C-t" :desc "Delete workspace" :nv "x" #'+workspace/kill)
  (map! :map magit-mode-map :prefix "C-t" :desc "Next workspace" :nv "n" #'+workspace/switch-right)
  (map! :map magit-mode-map :prefix "C-t" :desc "Previous workspace" :nv "p" #'+workspace/switch-left)
  (map! :map magit-mode-map :prefix "C-t" :desc "Switch to workspace" :nv "T" #'+workspace/switch-to)
  (map! :map magit-mode-map :prefix "C-t" :desc "Switch to workspace" :nv "t" #'+workspace/other)
  (map! :map magit-mode-map :prefix "g" :desc "Switch to other workspace" :nv "t" #'+workspace/other)
  (map! :map magit-mode-map :prefix "C-t" :desc "Load workspace from file" :nv "L" #'+workspace/load)
  (map! :map magit-mode-map :prefix "C-t" :desc "List workspaces" :nv "l" #'+workspace/switch-to)
  (map! :map magit-mode-map :prefix "C-t" :desc "List workspaces" :nv "R" #'+workspace/restore-last-session)
  (map! :map magit-mode-map :prefix "C-t" :desc "Rename workspace" :nv "r" #'+workspace/rename)
  (map! :map magit-mode-map :prefix "C-t" :desc "Rename workspace" :nv "," #'+workspace/rename)
  (map! :map magit-mode-map :prefix "C-t" :desc "New workspace" :nv "C-c" #'+workspace/new)
  (map! :map magit-mode-map :prefix "C-t" :desc "Delete workspace" :nv "C-x" #'+workspace/kill)
  (map! :map magit-mode-map :prefix "C-t" :desc "Next workspace" :nv "C-n" #'+workspace/switch-right)
  (map! :map magit-mode-map :prefix "C-t" :desc "Previous workspace" :nv "C-p" #'+workspace/switch-left)
  (map! :map magit-mode-map :prefix "C-t" :desc "Switch to other workspace" :nv "C-t" #'+workspace/other)
  (map! :map magit-mode-map :prefix "C-t" :desc "Load workspace from file" :nv "C-L" #'+workspace/load)
  (map! :map magit-mode-map :prefix "C-t" :desc "List workspaces" :nv "C-l" #'+workspace/switch-to)
  (map! :map magit-mode-map :prefix "C-t" :desc "List workspaces" :nv "C-R" #'+workspace/restore-last-session)
  (map! :map magit-mode-map :prefix "C-t" :desc "Rename workspace" :nv "C-r" #'+workspace/rename)
  (map! :map magit-mode-map :prefix "C-t" :desc "Rename workspace" :nv "C-," #'+workspace/rename)
  (map! :map magit-diff-mode-map :prefix "C-w" :nv "k" #'evil-window-down)
  (map! :map magit-diff-mode-map :prefix "C-w" :nv "h" #'evil-window-up)
  (map! :map magit-diff-mode-map :prefix "C-w" :nv "j" #'evil-window-left)
  (map! :map magit-diff-mode-map :prefix "C-w" :nv "l" #'evil-window-right)
  (map! :leader :prefix "g" :desc "Diff buffer file" :m "d" #'magit-diff-buffer-file)
  (map! :leader :prefix "g" :desc "Push a branch" :m "P" #'magit-push)
  (map! :leader :prefix "g" :desc "Pull a branch" :m "p" #'magit-pull)
  (map! :leader :prefix "g" :desc "PR to worktree" :m "w" #'forge-checkout-worktree)
  (map! :leader :prefix "g" (:prefix "W" :desc "Delete worktree" :m "k" #'magit-worktree-delete))
  (map! :leader :prefix "g" (:prefix "W" :desc "Move worktree" :m "m" #'magit-worktree-move))
  (map! :leader :prefix "g" (:prefix "c" :desc "Checkout branch" :m "o" #'magit-branch-checkout))
  (map! :leader :prefix "g" (:prefix "l" :desc "Git log at branch" :m "l" #'magit-log-current))
  (map! :leader :prefix "g" (:prefix "c" :desc "Amend commit" :m "a" #'magit-commit-amend)))

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

(add-hook! 'code-review-mode-hook
  (map! :map code-review-mode-map :nv "k" #'evil-next-line)
  (map! :map code-review-mode-map :nv "h" #'evil-previous-line))

(after! so-long
  (map! :map so-long-mode-map
        :nv "h" #'evil-previous-visual-line
        :nv "k" #'evil-next-visual-line
        :nv "j" #'evil-backward-char
        :nv "l" #'evil-forward-char))

(add-hook! 'magit-process-mode-hook
           ;; so that pressing '`' again doesn't open a second magit-process buffer but closes the existing one
           (map! :map magit-process-mode-map :nv "`" #'+magit/quit))

(add-hook! 'magit-section-movement-hook 'magit-log-maybe-update-blob-buffer)
(add-hook! 'magit-blame-read-only-mode-hook
           #'(lambda ()
               (map! :map magit-blame-read-only-mode-map :nv "k" #'evil-next-line)
               (map! :map magit-blame-read-only-mode-map :nv "h" #'evil-previous-line)
               (map! :map magit-blame-read-only-mode-map :nv "C-k" #'magit-blame-next-chunk)
               (map! :map magit-blame-read-only-mode-map :nv "C-h" #'magit-blame-previous-chunk)
               (map! :map magit-blame-read-only-mode-map :nv "C-e" #'evil-scroll-line-down)
               (map! :map magit-blame-read-only-mode-map :nv "C-y" #'evil-scroll-line-up)
               (map! :map magit-blame-read-only-mode-map :nv "g K" #'magit-blame-next-chunk-same-commit)
               (map! :map magit-blame-read-only-mode-map :nv "g H" #'magit-blame-previous-chunk-same-commit)
               (map! :map magit-blame-read-only-mode-map :nv "g k" #'magit-blame-next-chunk)
               (map! :map magit-blame-read-only-mode-map :nv "g h" #'magit-blame-previous-chunk)))
(add-hook! 'git-rebase-mode-hook
           #'(lambda ()
               (map! :map git-rebase-mode-map :nv "k" #'evil-next-line)
               (map! :map git-rebase-mode-map :nv "h" #'evil-previous-line)
               (map! :map git-rebase-mode-map :nv "gk" #'git-rebase-move-line-down)
               (map! :map git-rebase-mode-map :nv "gh" #'git-rebase-move-line-up)
               (map! :map git-rebase-mode-map :nv "C-k" #'git-rebase-move-line-down)
               (map! :map git-rebase-mode-map :nv "C-h" #'git-rebase-move-line-up)))

(map! :map '(magit-status-mode-map forge-topic-mode-map)
      :leader
      :desc "Start code review"
      :g "g v" '+magit/start-code-review)

;; (map! :map magit-status-mode-map :nv "RET" #'forge-visit-topic) ; this also overrides visiting diff at point we don't want that

(add-hook! 'magit-status-mode-hook
  (projectile-add-known-project (magit-toplevel)))

(add-hook! 'forge-post-mode-hook
  (auto-fill-mode -1))

(add-hook! 'code-review-mode-hook
           #'(lambda ()
               ;; include *Code-Review* buffer into current workspace
               (persp-add-buffer (current-buffer))))

;; Use Claude Code CLI for gptel-magit features instead of gptel.
;; Overrides `gptel-magit--generate' and `gptel-magit--do-diff-request'.
(after! gptel-magit
  (defun +llm--claude-code-request (input system-prompt append-prompt callback error-prefix &optional model)
    "Send INPUT to Claude Code CLI and call CALLBACK with the result text.
SYSTEM-PROMPT and APPEND-PROMPT are passed as --system-prompt and
--append-system-prompt respectively.  ERROR-PREFIX labels minibuffer
error messages.  MODEL is an optional claude CLI model alias or full
model ID, defaulting to \"haiku\"."
    (let* ((input-file (make-temp-file "claude-input-"))
           (output ""))
      (with-temp-file input-file (insert input))
      (make-process
       :name "claude-request"
       :command (list "sh" "-c"
                      (format "claude -p --output-format json --model %s --system-prompt %s --append-system-prompt %s --no-session-persistence < %s"
                              (shell-quote-argument (or model "haiku"))
                              (shell-quote-argument system-prompt)
                              (shell-quote-argument append-prompt)
                              (shell-quote-argument input-file)))
       :noquery t
       :filter (lambda (_proc str)
                 (setq output (concat output str)))
       :sentinel (lambda (_proc event)
                   (delete-file input-file t)
                   (if (string-prefix-p "finished" event)
                       (let* ((json-line (car (split-string output "\n")))
                              (result (gethash "result" (json-parse-string json-line))))
                         (funcall callback (string-trim result)))
                     (message "%s error: %s%s"
                              error-prefix
                              (string-trim event)
                              (if (string-empty-p output) ""
                                (concat "\n" output))))))))

  (defadvice! +llm--claude-code-magit-generate-a (callback)
    :override #'gptel-magit--generate
    (message "claude: Generating commit message...")
    (+llm--claude-code-request
     (magit-git-output "diff" "--cached")
     (gptel-magit--get-commit-prompt)
     "Output ONLY the raw commit message. No preamble, no markdown code fences, no Co-Authored-By trailer, no explanation."
     callback
     "claude-commit"))

  (defadvice! +llm--claude-code-magit-diff-explain-a (diff)
    :override #'gptel-magit--do-diff-request
    (message "claude: Explaining diff...")
    (+llm--claude-code-request
     diff
     gptel-magit-diff-explain-prompt
     "Output ONLY the explanation in Markdown. No preamble like \"Here is the explanation\"."
     #'gptel-magit--show-diff-explain
     "claude-diff-explain")))

(after! button
  (map! :map button-map :nv "o" #'push-button))

(after! doom-themes
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t))

(after! doom-modeline
  (setq doom-modeline-icon t)
  (setq doom-modeline-persp-name t))

(after! (:and eww org)
  (defun zz/eww-to-org (&optional dest)
    "Render the current eww buffer using org markup.
  If DEST, a buffer, is provided, insert the markup there."
    (interactive)
    (unless (org-region-active-p)
      (let ((shr-width 80)) (eww-readable)))
    (let* ((start (if (org-region-active-p) (region-beginning) (point-min)))
           (end (if (org-region-active-p) (region-end) (point-max)))
           (buff (or dest (generate-new-buffer "*eww-to-org*")))
           (link (eww-current-url))
           (title (or (plist-get eww-data :title) "")))
      (with-current-buffer buff
        (insert "#+title: " title "\n#+link: " link "\n\n")
        (org-mode))
      (save-excursion
        (goto-char start)
        (while (< (point) end)
          (let* ((p (point))
                 (props (text-properties-at p))
                 (k (seq-find (lambda (x) (plist-get props x))
                              '(shr-url image-url outline-level face)))
                 (prop (and k (list k (plist-get props k))))
                 (next (if prop
                           (next-single-property-change p (car prop) nil end)
                         (next-property-change p nil end)))
                 (txt (buffer-substring (point) next))
                 (txt (replace-regexp-in-string "\\*" "·" txt)))
            (with-current-buffer buff
              (insert
               (pcase prop
                 ((and (or `(shr-url ,url) `(image-url ,url))
                       (guard (string-match-p "^http" url)))
                  (let ((tt (replace-regexp-in-string "\n\\([^$]\\)" " \\1" txt)))
                    (org-link-make-string url tt)))
                 (`(outline-level ,n)
                  (concat (make-string (- (* 2 n) 1) ?*) " " txt "\n"))
                 ('(face italic) (format "/%s/ " (string-trim txt)))
                 ('(face bold) (format "*%s* " (string-trim txt)))
                 (_ txt))))
            (goto-char next))))
      (pop-to-buffer buff)
      (goto-char (point-min)))))

(after! org
  (require 'ox-gfm)
  (defun zz/org-insert-created-date (&rest ignore)
    "Insert an org-mode \":LOGBOOK:\" drawer with a \"CREATED:\" date and timestamp.

The \"CREATED\" field value is an inactive long-form
date/timestamp value with the current date and time. The user
will not be prompted to adjust these.

Intended to be installed as \"after\" advice around
`org-insert-todo-heading'.

Example:

    ** TODO
       :LOGBOOK:
       - CREATED: [2019-03-13 Wed 21:14]
       :END:

Note that point is one space beyond \"TODO\" both when M-S-RET is
pressed and when the function returns.

The implementation is naive in that it makes assumtions about
where it is in the buffer; a new set of lines will be inserted
below the current line unconditionally to hold the new drawer. No
effort is made to verify that the context in which the function
is invoked makes sense; no effort is made to detect an existing
drawer or any other content around point. The function assumes
that org-mode has just inserted a new TODO item and that point is
at the end of the headline.

Upon completion, point is restored to its location at the time
this function was invoked. If the above assumptions are correct,
this behavior should leave point at the end of the headline."
    (cl-flet ((zz/org-indent () (indent-to-column (1+ (org-outline-level)))))
      (save-excursion
        (insert "\n")
        (org-indent-line)
        (insert ":LOGBOOK:\n")
        (org-indent-line)
        (insert (format "- CREATED: %s\n"
                        (format-time-string (org-time-stamp-format 'long 'inactive)
                                            (org-current-effective-time))))
        (insert ":END:\n")
        (org-indent-drawer))))
  (advice-add 'org-insert-todo-heading :after #'zz/org-insert-created-date)

  (setq org-latex-compiler "xelatex")
  (setq org-latex-src-block-backend 'engraved)
  (setq org-latex-engraved-theme 'doom-one-light)
  (setq org-latex-inputenc-alist '(("utf8" . "utf8x")))
  (setq org-log-into-drawer t)
  (setq org-hide-emphasis-markers t)
  (setq org-todo-keywords '((sequence "BACKLOG(b!)" "TODO(t!)" "STARTED(s!)" "HOLD(h@/!)" "|" "DONE(d!)" "DROPPED(k@)")
                            (sequence "[ ](T)" "[-](S)" "[?](H)" "|" "[X](D)")
                            (sequence "|" "OKAY(o)" "YES(y)" "NO(n)")))
  (setq org-todo-keyword-faces '(("[-]" . +org-todo-active)
                                 ("STARTED" . +org-todo-active)
                                 ("[?]" . +org-todo-onhold)
                                 ("HOLD" . +org-todo-onhold)
                                 ("NO" . +org-todo-cancel)
                                 ("DROPPED" . +org-todo-cancel)))
  (setq org-capture-templates
        '(("t" "Projectless task" entry
           (file+headline +org-capture-todo-file "Inbox")
           "* BACKLOG %?\n:LOGBOOK:\n- CREATED: %U\n:END:\n%i\n%a" :heading "Tasks" :prepend nil)
          ("T" "Personal todo" entry
           (file+headline +org-capture-todo-file "Inbox")
           "* [ ] %?\n%i\n%a" :prepend t)
          ("n" "Personal notes" entry
           (file+headline +org-capture-notes-file "Inbox")
           "* %u %?\n%i\n%a" :prepend t)
          ("j" "Journal" entry
           (file+olp+datetree +org-capture-journal-file)
           "* %U %?\n%i\n%a" :prepend t)
          ("p" "Templates for projects")
          ("pt" "Project-local todo" entry
           (file+headline +org-capture-project-todo-file "Inbox")
           "* TODO %?\n:LOGBOOK:\n- CREATED: %U\n:END:\n%i\n%a" :prepend t)
          ("pn" "Project-local notes" entry
           (file+headline +org-capture-project-notes-file "Inbox")
           "* %U %?\n%i\n%a" :prepend t)
          ("pc" "Project-local changelog" entry
           (file+headline +org-capture-project-changelog-file "Unreleased")
           "* %U %?\n%i\n%a" :prepend t)
          ("o" "Centralized templates for projects")
          ("ot" "Project todo" entry #'+org-capture-central-project-todo-file
           "* TODO %?\n:LOGBOOK:\n- CREATED: %U\n:END:\n %i\n %a" :heading "Tasks" :prepend nil)
          ("on" "Project notes" entry #'+org-capture-central-project-notes-file
           "* %U %?\n %i\n %a" :heading "Notes" :prepend t)
          ("oc" "Project changelog" entry #'+org-capture-central-project-changelog-file
           "* %U %?\n %i\n %a" :heading "Changelog" :prepend t))))

(after! evil-org
  (map! :map evil-org-mode-map
        :nvi "M-h" #'org-metaup
        :nvi "M-k" #'org-metadown
        :nvi "M-j" #'org-metaleft
        :nvi "M-l" #'org-metaright
        :nvi "M-H" #'org-shiftmetaup
        :nvi "M-K" #'org-shiftmetadown
        :nvi "M-J" #'org-shiftmetaleft
        :nvi "M-L" #'org-shiftmetaright
        :nv "g k" #'evil-next-visual-line
        :nv "g h" #'evil-previous-visual-line
        :nv "g K" #'org-forward-element
        :nv "g H" #'org-backward-element
        :nv "g J" #'org-up-element
        :nv "C-k" #'org-forward-element
        :nv "C-h" #'org-backward-element
        :nv "C-j" #'org-up-element
        :nv "C-l" #'org-down-element))

(after! evil-org-agenda
  (map! :map evil-org-agenda-mode-map :m "o" #'org-agenda-switch-to)
  (map! :map evil-org-agenda-mode-map :m "k" #'org-agenda-next-line)
  (map! :map evil-org-agenda-mode-map  :m "h" #'org-agenda-previous-line)
  ;; Disables 'j' and 'l' so that evil-motion bindings are used for left and right movement
  (map! :map evil-org-agenda-mode-map :m "j" nil)
  (map! :map evil-org-agenda-mode-map :m "l" nil)
  (map! :map evil-org-agenda-mode-map :m "M-h" #'org-agenda-drag-line-backward)
  (map! :map evil-org-agenda-mode-map :m "M-k" #'org-agenda-drag-line-backward))

(after! org-crypt
  (setq org-crypt-key user-mail-address))

(add-hook! (org-mode markdown-mode git-commit-mode)
           #'(lambda ()
               (set-fill-column 78)
               (auto-fill-mode 1)))

(after! markdown
  (map! :map markdown-mode-map :m "M-h" #'markdown-move-up)
  (map! :map markdown-mode-map :m "M-k" #'markdown-move-down))

(after! evil-markdown
  (map! :map evil-markdown-mode-map
        :nv "g k" #'evil-next-visual-line
        :nv "g h" #'evil-previous-visual-line))

(add-hook! c-mode
  (add-to-list 'c-default-style '(c-mode . "bsd"))
  (add-to-list 'c-default-style '(cc-mode . "bsd"))
  (set-formatter!
    'clang-format
    '("clang-format" "--style" "Webkit" "--assume-filename"
      (or
       (buffer-file-name)
       ".c"))
    :modes '(c-mode)))

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

(add-hook! yaml-mode
           #'(lambda ()
               ;; in yaml-mode attributes/keys seem to be recognized as strings and thus spell checked which isn't very useful
               ;; but if there could be a face for yaml attributes then we could add that face into the list of excluded faces
               ;; and we could check for spelling in actual strings and comments in YAML files
               (spell-fu-mode -1)))

(after! spell-fu
  ;; TODO workround for https://github.com/doomemacs/doomemacs/issues/6246
  (unless (file-exists-p ispell-personal-dictionary)
    (make-directory (file-name-directory ispell-personal-dictionary) t)
    (with-temp-file ispell-personal-dictionary
      (insert (format "personal_ws-1.1 %s 0\n" ispell-dictionary)))))

(add-hook! 'spell-fu-mode-hook
           #'(lambda ()
               (spell-fu-dictionary-add (spell-fu-get-ispell-dictionary "spanish"))))

(after! sql
  (defun zz/insert-on-psql ()
    (interactive)
    (evil-goto-line)
    (evil-append-line 1))
  (map! :mode sql-interactive :map sql-interactive-mode-map
        :n "q" #'zz/insert-on-psql
        :n "i" #'zz/insert-on-psql
        :prefix "C-c" :desc "Execute SQL query" :im "C-c" #'sql-send-paragraph
        :localleader :desc "Execute SQL query" :m "x" #'sql-send-paragraph)
  (map! :localleader :prefix "l"
        :desc "Describe table" :nv "t" #'sql-list-table
        :desc "List tables" :nv "a" #'sql-list-all))

(add-hook! sql-mode
  (set-formatter!
    'sqlfluff
    '("sqlfluff" "format"
      "--processes" "0" "--disable-progress-bar" "--stdin-filename" "--nocolor"
      "-")
    :modes '(sql-mode)))

(add-hook! haskell-mode
  (set-fill-column 100))

(add-hook! haskell-literate-mode 'lsp)

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

(after! drag-stuff
  (map! :map drag-stuff-mode-map :desc "Drag stuff up" :nv "M-h" #'drag-stuff-up)
  (map! :map drag-stuff-mode-map :desc "Drag stuff up" :nv "M-k" #'drag-stuff-down))

(add-hook! pdf-view-mode
  (map! :map pdf-view-mode-map
        :nv "l" #'image-forward-hscroll
        :nv "j" #'image-backward-hscroll
        :nv "k" #'pdf-view-next-line-or-next-page
        :nv "h" #'pdf-view-previous-line-or-previous-page))

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

(after! c-mode
  (map! :map c-mode-map :localleader :m "h" #'woman-follow)
  (map! :map c-mode-map :localleader :m "H" #'woman))

(after! lua-mode
  (setopt lsp-clients-lua-language-server-bin (executable-find "lua-language-server")))

;; TODO what's the doom way to configure this?
(add-to-list 'auto-mode-alist '("\\.vim\\(rc\\)?\\'" . vimrc-mode))
(add-to-list 'auto-mode-alist '("\\.nomad\\(?:\\.tftpl\\)?\\'" . hcl-mode))

(after! sly
  ;; TODO This function is not sly specific, could be used for vterm as well
  (defun zz/insert-on-repl ()
    (interactive)
    (evil-goto-line)
    (evil-append-line 1))
  (map! :map sly-mrepl-mode-map :i "C-r" #'isearch-backward)
  (map! :map sly-mrepl-mode-map :i "C-l" #'evil-scroll-line-to-top)
  (map! :map sly-mrepl-mode-map :i "C-k" #'kill-line)
  (map! :map sly-mrepl-mode-map :i "C-p" #'sly-mrepl-previous-input-or-button)
  (map! :map sly-mrepl-mode-map :i "C-n" #'sly-mrepl-next-input-or-button)
  (map! :map sly-mrepl-mode-map :n "q" #'zz/insert-on-repl)
  (map! :map sly-mrepl-mode-map :n "i" #'zz/insert-on-repl))

(add-hook! lispyville-mode
  (map! :map lispyville-mode-map
        :n "M-h" #'drag-stuff-up
        :n "M-k" #'drag-stuff-down
        :n "M-j" #'lispyville-drag-backward
        :n "M-l" #'lispyville-drag-forward))

(add-hook! lisp-data-mode
  (lispy-mode 1)
  (lispyville-mode 1))

(after! cider
  (add-hook! clojure-mode
    (add-hook! 'after-save-hook :local #'cider-ns-refresh))
  (require 'kaocha-runner)
  (setopt cider-save-file-on-load t
         cider-ns-save-files-on-refresh t)
  ;; TODO `i` should handle when cursor is in read-only vs writable region
  (map! :map cider-repl-mode-map :n "i" #'evil-goto-line)
  (map! :map cider-repl-mode-map :ni "C-p" #'cider-repl-backward-input)
  (map! :map cider-repl-mode-map :ni "C-n" #'cider-repl-next-input)
  (map! :map cider-mode-map :localleader :prefix "t"
        :desc "Kaocha test at point" :nv "T" #'kaocha-runner-run-test-at-point
        :desc "Kaocha test ns" :nv "N" #'kaocha-runner-run-tests
        :desc "Kaocha test project" :nv "P" #'kaocha-runner-run-all-tests))


(add-hook! emmet-mode
  (map! :map emmet-mode-keymap :prefix "C-e" :desc "Emmet expand" :i "," #'emmet-expand-line))

;; TODO Variables manually set work but with the hook it seems they get ignored? explore the keymaps
(after! vterm
  (when (file-exists-p "~/.nix-profile/bin/zsh")
    (setopt vterm-shell (expand-file-name "~/.nix-profile/bin/zsh")))
  (defun zz-vterm-reset-cursor-point-insert ()
    (interactive)
    (let ((prompt-line (save-excursion
                         (vterm-reset-cursor-point)
                         (what-line))))
      (if (string= (what-line) prompt-line)
          (evil-collection-vterm-insert)
        (vterm-reset-cursor-point)
        (vterm-send-key (kbd "C-e"))
        (evil-collection-vterm-insert))))
  (map! :map vterm-mode-map :n "M-:" #'eval-expression)
  (map! :map vterm-mode-map :n "q" #'zz-vterm-reset-cursor-point-insert)
  (map! :map vterm-mode-map :v "q" #'(lambda ()
                                       (interactive)
                                       (evil-exit-visual-state)
                                       (zz-vterm-reset-cursor-point-insert)))
  (map! :map vterm-mode-map :prefix "C-t" :i "[" #'evil-normal-state)
  (map! :map vterm-mode-map :prefix "C-t" :ni "]" #'evil-collection-vterm-paste-after)
  (map! :map vterm-mode-map :n "i" #'zz-vterm-reset-cursor-point-insert)
  (map! :map vterm-mode-map :nv "k" #'evil-collection-vterm-next-line)
  (map! :map vterm-mode-map :nv "l" #'evil-forward-char)
  (map! :map vterm-mode-map :nv "j" #'evil-backward-char))

(add-hook! vterm-mode :local
  (setopt evil-normal-state-cursor '(box "cornsilk"))
  (setopt evil-insert-state-cursor '(box "DarkGoldenrod")))

;; TODO doesn't really work for haskell (it asks for a file to be selected)
;; (after! compile
;;   (setopt compilation-auto-jump-to-first-error t))

(add-hook! vterm-mode
  (display-line-numbers-mode -1)
  (compilation-shell-minor-mode))

(after! (:or compile vterm)
  (map! :map compilation-shell-minor-mode-map :prefix "g" :n "." #'compilation-next-error-function))

(after! gptel
  (setopt gptel-model 'fastgpt
          gptel-backend (gptel-make-kagi "Kagi" :key #'gptel-api-key-from-auth-source)))

(after! claude-code-ide
  (setq claude-code-ide-window-side 'right
        claude-code-ide-window-width 90)
  (claude-code-ide-emacs-tools-setup))

(after! linear-emacs
  (setopt linear-emacs-api-key (zz/auth-info-key "api.linear.app" "apikey")))

(add-hook! 'Info-mode-hook
  (map! :map Info-mode-map :nv "o" #'Info-follow-nearest-node))

;; When connecting via emacsclient, start the frame fullscreen and fix theme cursor colors.
;; We use `set-frame-parameter' instead of `toggle-frame-fullscreen' to avoid toggling —
;; tools like Magit's with-editor can trigger this hook a second time (for their own
;; internal frames), and a toggle would exit fullscreen on the existing frame.
;; Avoid `(add-to-list 'default-frame-alist '(fullscreen . fullboth))' as that triggers
;; a theme cursor color bug. See: https://github.com/doomemacs/doomemacs/issues/6221
(add-hook! 'server-after-make-frame-hook
  (when (display-graphic-p)
    (set-frame-parameter nil 'fullscreen 'fullboth))
  (consult-theme doom-theme)
  (global-disable-mouse-mode 1)
  (mapc #'disable-mouse-in-keymap
        (list evil-insert-state-map)))

;; This hooks only runs on startup, it won't run when connecting via emacsclient that's fine here
(add-hook! 'window-setup-hook :append
           #'(lambda ()
               (when (display-graphic-p)
                 (toggle-frame-fullscreen))
               (global-disable-mouse-mode 1)
               (mapc #'disable-mouse-in-keymap
                     (list evil-insert-state-map))))

(defun zz-forge-checkout-worktree (orig-fun &rest orig-args)
  "Meant to be used as an advice to `forge-checkout-worktree' in which the
created worktree is added as a projectile project and switch to it after
checkout."
  (forge-pull)
  (let ((the-path (car orig-args))
        (+workspaces-switch-project-function #'(lambda (the-project-path)
                                                 (magit-status-setup-buffer the-project-path)
                                                 (lsp-workspace-folders-add the-project-path)))
        (+workspaces-switch-project-function #'magit-status))
    (apply orig-fun orig-args)
    (projectile-add-known-project the-path)
    (projectile-switch-project-by-name the-path)))

(advice-add 'forge-checkout-worktree :around #'zz-forge-checkout-worktree)

(defun zz-projectile-invalidate-cache (&rest _args)
  "We want to invalidate projectile cache after checking out a branch since
files might be at different locations."
  ;; We ignore the args to `magit-checkout' (the adviced function).
  (projectile-invalidate-cache nil))

(advice-add 'magit-checkout :after #'zz-projectile-invalidate-cache)
(advice-add 'magit-branch-and-checkout :after #'zz-projectile-invalidate-cache)


;; NOTE Workaround while this is fixed https://dev.gnupg.org/T6481
;; NOTE #2 It should work now without this granted the gpg nix patch worked
;; (add-hook! 'authinfo-mode-hook
;;   (fset 'epg-wait-for-status 'ignore))

;; TODO There's an annoying pop-up when saving (auto formatting) yaml files because doesn't resolve anchors correctly
;; TODO "TAB" in sql-mode does not work to ident, e.g. try to write "ON" after "JOIN" in a new line indenting it
;; TODO Formatting on save for Haskell is done weirdly try to re-configure using "apheleia"
;; TODO Emmet not working (not loading rather), observed in *.tsx files
;; TODO in buffers named *format-all-errors* want 'q' to quit the buffer
;; TODO Fix colemak bindings for evil-easy-motion-next-line and prev-line
;; TODO Fix 'i' to jump at prompt in sql-postgres buffers
;; TODO Auto format elisp code on save (none of the fmts are good maybe just select buffer and run '=' on selected lines)
;; TODO Make utility to copy current module name (like 'SPC f y' but for full module path) language agnostic
