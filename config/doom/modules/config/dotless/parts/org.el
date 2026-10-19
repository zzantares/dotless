;;; parts/org.el -*- lexical-binding: t; -*-

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
  (setq org-latex-engraved-theme nil)
  (setq org-latex-inputenc-alist '(("utf8" . "utf8x")))
  (add-to-list 'org-latex-default-packages-alist '("" "xcolor" nil))
  (add-to-list 'org-latex-default-packages-alist '("" "fontspec" t ("xelatex" "lualatex")))
  (setq org-latex-hyperref-template
        "\\definecolor{linkblue}{rgb}{0.1,0.1,0.5}\n\\hypersetup{\n pdfauthor={%a},\n pdftitle={%t},\n pdfkeywords={%k},\n pdfsubject={%d},\n pdfcreator={%c},\n pdflang={%L},\n colorlinks=true,\n linkcolor=linkblue,\n urlcolor=linkblue,\n citecolor=linkblue}\n")
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
