;;; parts/notmuch.el -*- lexical-binding: t; -*-

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
