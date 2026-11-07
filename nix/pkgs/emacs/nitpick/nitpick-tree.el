;;; nitpick-tree.el --- A treemacs pane of the files a review changed -*- lexical-binding: t; -*-

;; Author: dotless
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (magit "4.0") (treemacs "3.0"))
;; Keywords: vc, tools
;; URL: https://git.gutimore.net/gutimore/dotless

;;; Commentary:

;; A side pane listing only the files that differ from the revision under
;; review, nested by directory, with each file's status and line counts.  The
;; same thing diffnav shows next to its diff, for the review nitpick anchors on
;; the files on disk: RET opens the real file, where diff-hl has already painted
;; what the revision changed.
;;
;; One command, `nitpick-tree', which also refreshes the pane it opened.  The
;; revision is the one `nitpick-diff-hl-set-base' last picked for this worktree,
;; so the pane lists exactly the files diff-hl is painting; a prefix argument
;; asks for another.
;;
;; treemacs is required at run time only.  Its node-type definitions are macros,
;; so they are evaluated once treemacs loads rather than compiled in here, the
;; same way nitpick waits for diff-hl before advising it.  Everything the
;; definitions call is a function in this file, byte-compiled as usual.

;;; Code:

(require 'nitpick)
(require 'seq)

(declare-function magit-toplevel "magit-git" (&optional directory))
(declare-function magit-git-insert "magit-git" (&rest args))
(declare-function magit-read-branch-or-commit "magit-git" (prompt &optional secondary-default exclude))
(declare-function magit-find-file-noselect "magit-files" (rev file &optional no-restore-position volatile))
(declare-function magit-diff-range "magit-diff" (rev-or-range &optional args files))
(declare-function magit-diff-arguments "magit-diff" (&optional mode))
(declare-function treemacs-node-at-point "treemacs-core-utils" ())
(declare-function treemacs-expand-extension-node "treemacs-treelib" (&optional arg))
(declare-function treemacs-icon-for-file "treemacs-icons" (file))
(declare-function treemacs-icon-for-dir "treemacs-icons" (dir state))
(declare-function treemacs-collapse-extension-node "treemacs-treelib" (&optional arg))
(declare-function diff-hl-update "diff-hl" ())
(declare-function diff-hl-next-hunk "diff-hl" (&optional backward))
(defvar diff-hl-mode)
(defvar diff-hl-update-async)
(defvar treemacs--open-node-states)
(defvar treemacs-position)
(defvar treemacs-space-between-root-nodes)
(defvar treemacs-width)

;; Defined by `nitpick-tree--definitions', which treemacs' macros can only
;; expand once treemacs itself is loaded.
(declare-function nitpick-tree--render "nitpick-tree" (root revision items stats))

;;;; Options

(defcustom nitpick-tree-buffer-name "*nitpick-tree*"
  "Name of the buffer the changed-file pane is rendered in.
One pane, re-rendered per project, the way treemacs shows one tree."
  :type 'string
  :group 'nitpick)

(defcustom nitpick-tree-collapse-dirs t
  "Whether to draw a chain of single-child directories as one node.
`nix/pkgs/emacs' on one line instead of three.  treemacs does this for real
directories through `treemacs-collapse-dirs'; an extension has to do its own."
  :type 'boolean
  :group 'nitpick)

(defcustom nitpick-tree-show-untracked t
  "Whether to list untracked files alongside the ones git diffs.
They are not part of `git diff', so the forge will not show them either - but
a file you forgot to add is the one most worth seeing before you submit.  They
carry no line counts, only the `?' marker."
  :type 'boolean
  :group 'nitpick)

(defcustom nitpick-tree-visit-jumps-to-hunk t
  "Whether opening a file from the pane moves point to its first change.
The file opens at its first changed line instead of wherever it was left, so
reading a review is one RET per file.  Needs `diff-hl-mode' in that buffer."
  :type 'boolean
  :group 'nitpick)

(defface nitpick-tree-insertions '((t :inherit diff-added))
  "Face for a file's added-line count."
  :group 'nitpick)

(defface nitpick-tree-deletions '((t :inherit diff-removed))
  "Face for a file's removed-line count."
  :group 'nitpick)

(defface nitpick-tree-status '((t :inherit shadow))
  "Face for the status marker of a file that was not simply modified."
  :group 'nitpick)

(defface nitpick-tree-revision '((t :inherit font-lock-constant-face))
  "Face for the revision named in the pane's header line."
  :group 'nitpick)

;;;; Buffer-local state
;;
;; Set from `:and-do', which runs after `treemacs-mode' has wiped the buffer's
;; locals and before the first `:children' call reads them back.

(defvar-local nitpick-tree--root nil
  "Project root the pane was rendered for.")

(defvar-local nitpick-tree--revision nil
  "Revision, as picked, the pane lists the differences from.")

(defvar-local nitpick-tree--items nil
  "The pane's top-level nodes, as built by `nitpick-tree--build'.")

;;;; Reading the diff out of git

(defun nitpick-tree--git-output (&rest args)
  "Return the output of git ARGS as a string.
Every caller passes `-z', so paths arrive raw: git quotes a path with odd
characters in it in every other format, and the quoting is not undone here."
  (with-temp-buffer
    (apply #'magit-git-insert args)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun nitpick-tree--parse-name-status (out)
  "Parse OUT, the `-z' output of `git diff --name-status'.
Return an alist of (PATH . STATUS), STATUS as git spells it - a letter, or a
letter and a similarity index for a rename.  A rename names two paths, old
then new; the new one is where the file is now, so that is the one kept, with
the old one recorded next to it: (PATH STATUS . OLD-PATH)."
  (let ((fields (split-string out "\0" t))
        acc)
    (while (cdr fields)
      (let* ((status (pop fields))
             (renamed (memq (aref status 0) '(?R ?C)))
             (old (and renamed (pop fields)))
             (path (pop fields)))
        (push (if old (list path status old) (list path status)) acc)))
    (nreverse acc)))

(defconst nitpick-tree--numstat-re
  "\\`\\([0-9]+\\|-\\)\t\\([0-9]+\\|-\\)\t\\(.*\\)\\'"
  "What one `git diff --numstat -z' record looks like.
The counts are `-' for a binary file.  The path is empty when the record is a
rename, whose two paths follow as their own fields.")

(defun nitpick-tree--parse-numstat (out)
  "Parse OUT, the `-z' output of `git diff --numstat'.
Return an alist of (PATH ADDED . DELETED), the counts nil for a binary file.

Unlike `--name-status', a record here is not NUL-terminated field by field:
the counts and the path share one field, except for a rename, which ends the
field after the counts and follows it with the old and new paths.  Which is
why the split must keep empty fields - that empty path is the only thing
marking a rename."
  (let ((fields (split-string out "\0"))
        acc)
    (while fields
      (let ((field (pop fields)))
        (when (string-match nitpick-tree--numstat-re field)
          (let ((added (match-string 1 field))
                (deleted (match-string 2 field))
                (path (match-string 3 field)))
            (when (equal path "")
              (pop fields)                ; the old path
              (setq path (or (pop fields) "")))
            (unless (equal path "")
              (push (list path
                          (and (not (equal added "-")) (string-to-number added))
                          (and (not (equal deleted "-")) (string-to-number deleted)))
                    acc))))))
    (nreverse acc)))

(defun nitpick-tree--untracked ()
  "Return the untracked files in `default-directory''s repository."
  (split-string (nitpick-tree--git-output
                 "ls-files" "--others" "--exclude-standard" "-z")
                "\0" t))

(defun nitpick-tree--changes (root revision)
  "Return a plist per file that differs between REVISION and ROOT's worktree.
Each plist carries the repository-relative `:file', git's `:status' marker,
the `:added' and `:deleted' line counts, and `:from' for a rename.  REVISION
is resolved the way `nitpick-diff-hl-set-base' resolves it, trailing `...'
included, so the pane and diff-hl always agree on what is being compared."
  (let* ((default-directory root)
         (base (or (nitpick--base-revision revision)
                   (user-error "Cannot work out a merge base for %s" revision)))
         (stats (nitpick-tree--parse-numstat
                 (nitpick-tree--git-output "diff" "--numstat" "-z" base)))
         (files
          (mapcar
           (lambda (entry)
             (let* ((path (nth 0 entry))
                    (stat (assoc path stats)))
               (list :file path
                     :status (nth 1 entry)
                     :from (nth 2 entry)
                     :added (nth 1 stat)
                     :deleted (nth 2 stat)
                     ;; git diffed it and would not say by how much.
                     :binary (and stat (null (nth 1 stat)) (null (nth 2 stat))))))
           (nitpick-tree--parse-name-status
            (nitpick-tree--git-output "diff" "--name-status" "-z" base)))))
    (append files
            (and nitpick-tree-show-untracked
                 (mapcar (lambda (path) (list :file path :status "?"))
                         (nitpick-tree--untracked))))))

;;;; Folding the paths into a tree

(defun nitpick-tree--sort (nodes)
  "Return NODES with the directories first, each group by name."
  (sort nodes
        (lambda (a b)
          (let ((a-dir (plist-get a :dir))
                (b-dir (plist-get b :dir)))
            (if (eq (not a-dir) (not b-dir))
                (string-lessp (plist-get a :name) (plist-get b :name))
              (and a-dir t))))))

(defun nitpick-tree--nodes (entries dir)
  "Return the nodes DIR holds for ENTRIES.
ENTRIES is a list of (SEGMENTS . FILE): the path segments still to be folded,
and the file plist they came from.  Entries sharing a first segment are that
segment's node - a file when nothing follows the segment, else a directory
holding whatever the rest of the segments fold into.  A name cannot be both,
so a group is never mixed."
  (let (nodes)
    (dolist (group (seq-group-by (lambda (entry) (car (car entry))) entries))
      (let* ((name (car group))
             (members (cdr group))
             (path (expand-file-name name dir)))
        (push (if (cdr (car (car members)))
                  (list :name name :path path :dir t
                        :children (nitpick-tree--nodes
                                   (mapcar (lambda (entry)
                                             (cons (cdr (car entry)) (cdr entry)))
                                           members)
                                   path))
                (append (list :name name :path path :dir nil) (cdr (car members))))
              nodes)))
    (nitpick-tree--sort nodes)))

(defun nitpick-tree--collapse (nodes)
  "Return NODES with each chain of single-child directories folded into one.
Depth first, so a chain of any length collapses in the one pass: by the time a
directory is looked at, its own child has already swallowed everything below
it."
  (mapcar
   (lambda (node)
     (if (not (plist-get node :dir))
         node
       (let* ((children (nitpick-tree--collapse (plist-get node :children)))
              (only (and (null (cdr children)) (car children))))
         (if (and nitpick-tree-collapse-dirs only (plist-get only :dir))
             (list :name (concat (plist-get node :name) "/" (plist-get only :name))
                   :path (plist-get only :path)
                   :dir t
                   :children (plist-get only :children))
           (list :name (plist-get node :name)
                 :path (plist-get node :path)
                 :dir t
                 :children children)))))
   nodes))

(defun nitpick-tree--build (files root)
  "Return the tree ROOT's FILES fold into, as a list of top-level nodes."
  (nitpick-tree--collapse
   (nitpick-tree--nodes
    (mapcar (lambda (file)
              (cons (split-string (plist-get file :file) "/" t) file))
            files)
    root)))

;;;; What a node looks like

(defun nitpick-tree--counts (node)
  "Return NODE's line counts as a string, empty when it has none.
An untracked file has none, and a binary one says so instead: git diffs it
without ever saying by how much."
  (let ((added (plist-get node :added))
        (deleted (plist-get node :deleted)))
    (if (plist-get node :binary)
        (propertize " bin" 'face 'nitpick-tree-status)
      (concat (and added (> added 0)
                   (concat " " (propertize (format "+%d" added)
                                           'face 'nitpick-tree-insertions)))
              (and deleted (> deleted 0)
                   (concat " " (propertize (format "-%d" deleted)
                                           'face 'nitpick-tree-deletions)))))))

(defun nitpick-tree--marker (node)
  "Return NODE's status marker, empty for a plain modification.
`M' is what most of a review is, so drawing it on every line says nothing the
counts do not.  Anything else - added, deleted, renamed, untracked - is worth
a letter."
  (let ((status (plist-get node :status)))
    (if (or (null status) (equal status "M"))
        ""
      (concat " " (propertize (substring status 0 1) 'face 'nitpick-tree-status)))))

(defun nitpick-tree--label (node)
  "Return the text drawn after NODE's icon."
  (if (plist-get node :dir)
      (propertize (plist-get node :name) 'face 'treemacs-directory-face)
    (concat (propertize (plist-get node :name) 'face 'treemacs-file-face)
            (nitpick-tree--marker node)
            (nitpick-tree--counts node)
            (let ((from (plist-get node :from)))
              (and from (concat " " (propertize (concat "<- " from)
                                                'face 'nitpick-tree-status)))))))

(defun nitpick-tree--totals (files)
  "Return (COUNT ADDED DELETED) over FILES."
  (list (length files)
        (apply #'+ (delq nil (mapcar (lambda (f) (plist-get f :added)) files)))
        (apply #'+ (delq nil (mapcar (lambda (f) (plist-get f :deleted)) files)))))

(defun nitpick-tree--header (revision totals)
  "Return the pane's header line for REVISION and TOTALS."
  (let ((count (nth 0 totals)))
    (concat " vs " (propertize revision 'face 'nitpick-tree-revision)
            (format "  %d file%s" count (if (= count 1) "" "s"))
            (propertize (format " +%d" (nth 1 totals)) 'face 'nitpick-tree-insertions)
            (propertize (format " -%d" (nth 2 totals)) 'face 'nitpick-tree-deletions))))

;;;; Visiting

(defun nitpick-tree--node-at-point ()
  "Return the node plist of the pane's current line, or nil."
  (let ((btn (treemacs-node-at-point)))
    (and btn (get-text-property btn :nitpick-node))))

(defun nitpick-tree--show-hunk ()
  "Move point to the first change in the current buffer, if it has one.
diff-hl's own update is asked for synchronously first: a file opened a moment
ago has no overlays yet, and the asynchronous update would land after the
jump."
  (when (and nitpick-tree-visit-jumps-to-hunk (bound-and-true-p diff-hl-mode))
    (let ((diff-hl-update-async nil))
      (diff-hl-update))
    (goto-char (point-min))
    (ignore-errors (diff-hl-next-hunk))))

(defun nitpick-tree--visit-file (node stay)
  "Open NODE's file, selecting its window unless STAY is non-nil.
A deleted file is opened from the revision instead of from disk, where it is
no longer - read-only, the way magit shows a blob."
  (let* ((status (plist-get node :status))
         (buffer (if (equal status "D")
                     (let ((default-directory nitpick-tree--root))
                       (magit-find-file-noselect
                        (nitpick--base-revision nitpick-tree--revision)
                        (plist-get node :file)))
                   (find-file-noselect (plist-get node :path))))
         (window (display-buffer buffer)))
    (when (and window (not stay))
      (select-window window)
      (nitpick-tree--show-hunk))))

(defun nitpick-tree-visit (&optional arg)
  "Open the file on the current line, or fold the directory on it.
With a prefix ARG the file is shown but the pane keeps the focus, so a whole
review can be opened without leaving it."
  (interactive "P")
  (let ((node (nitpick-tree--node-at-point)))
    (cond
     ((null node) nil)
     ((not (plist-get node :dir)) (nitpick-tree--visit-file node arg))
     ((memq (get-text-property (treemacs-node-at-point) :state)
            treemacs--open-node-states)
      (treemacs-collapse-extension-node arg))
     (t (treemacs-expand-extension-node arg)))))

(defun nitpick-tree--diff-paths (node root)
  "Return the pathspec magit should limit NODE's diff to, relative to ROOT.
A directory limits the diff to everything under it.  A rename names both of
its paths: git pairs the two to recognise the rename, and asking for only
the new one shows an addition, or nothing at all."
  (if (plist-get node :dir)
      (list (file-relative-name (plist-get node :path) root))
    (delq nil (list (plist-get node :file) (plist-get node :from)))))

(defun nitpick-tree-visit-diff (&optional stay)
  "Show the diff of the line at point, instead of the file itself.

The file's changes against the pane's own revision, in a magit diff buffer -
the reading view, where removed lines are text and unchanged context is
folded away, next to `nitpick-tree-visit''s editing view of the same change.
On a directory it is the diff of everything under it.

With a prefix argument STAY the diff is shown but the pane keeps the focus."
  (interactive "P")
  (let ((node (nitpick-tree--node-at-point)))
    (when node
      (when (equal (plist-get node :status) "?")
        (user-error "%s is untracked: git has nothing to diff it against"
                    (plist-get node :file)))
      (let* ((root nitpick-tree--root)
             (revision (nitpick--base-revision nitpick-tree--revision))
             (files (nitpick-tree--diff-paths node root))
             (default-directory root)
             (show (lambda ()
                     ;; The user's own magit diff settings, so this diff reads
                     ;; like every other diff they look at.  `car': that
                     ;; function answers (ARGS FILES) - it fills both of the
                     ;; interactive slots - and its FILES is whatever the last
                     ;; magit diff was limited to, which git would then read as
                     ;; a revision.
                     (magit-diff-range revision (car (magit-diff-arguments))
                                       files))))
        (if stay (save-selected-window (funcall show)) (funcall show))))))

(defvar nitpick-tree-mode-map
  (let ((map (make-sparse-keymap)))
    ;; `d' is `treemacs-delete-file' in `treemacs-mode-map', and dead under
    ;; evil, whose motion state suppresses plain letters.  Shadowing it is
    ;; wanted either way: `d' reads a diff everywhere else, and deleting a
    ;; file out of a review pane is no accident to invite.
    (define-key map "d" #'nitpick-tree-visit-diff)
    map)
  "Keymap of the changed-file pane, on top of `treemacs-mode-map'.")

(define-minor-mode nitpick-tree-mode
  "Minor mode of the changed-file pane, for the keys that are only its own.
Enabled by `nitpick-tree'; it carries no behaviour of its own, and exists so
there is one keymap to rebind, and one mode for `evil-define-key' to hang an
auxiliary map on - under evil the map below is shadowed until something does,
because treemacs' evil state enables motion state, which binds every plain
letter to `undefined'."
  :lighter nil
  :keymap nitpick-tree-mode-map
  :group 'nitpick)

;;;; treemacs node types
;;
;; One monotyped node type, dispatching on whether an item is a directory,
;; because a type declares a single `:child-type': directories and files in the
;; same parent cannot be two types.  Files carry `:leaf' so TAB on one does
;; nothing instead of expanding an empty node.

(defconst nitpick-tree--definitions
  '(progn
     (treemacs-define-expandable-node-type nitpick-tree-node
       ;; `treemacs-icon-for-dir' and -for-file, not the theme's own tables:
       ;; these read the icon set treemacs built for this display, so a
       ;; terminal frame gets the text fallbacks instead of nothing.
       :closed-icon (if (plist-get item :dir)
                        (treemacs-icon-for-dir (plist-get item :path) 'closed)
                      (treemacs-icon-for-file (plist-get item :path)))
       :open-icon (if (plist-get item :dir)
                      (treemacs-icon-for-dir (plist-get item :path) 'open)
                    (treemacs-icon-for-file (plist-get item :path)))
       :label (nitpick-tree--label item)
       :key (plist-get item :path)
       :more-properties (if (plist-get item :dir)
                            (list :nitpick-node item)
                          (list :nitpick-node item :leaf t))
       :children (plist-get item :children)
       :child-type 'nitpick-tree-node
       :ret-action #'nitpick-tree-visit)

     (treemacs-define-variadic-entry-node-type nitpick-tree-root
       :key 'nitpick-tree-root
       :children nitpick-tree--items
       :child-type 'nitpick-tree-node)

     (defun nitpick-tree--render (root revision items stats)
       "Render ITEMS in the current buffer as the pane for ROOT and REVISION.
STATS is what `nitpick-tree--totals' returned, for the header line."
       (treemacs-initialize nitpick-tree-root
         :with-expand-depth 'all
         :and-do (progn
                   (setq-local nitpick-tree--root root
                               nitpick-tree--revision revision
                               nitpick-tree--items items
                               treemacs-space-between-root-nodes nil
                               header-line-format (nitpick-tree--header revision stats))
                   (nitpick-tree-mode 1)))))
  "The treemacs definitions, held as data until treemacs is loaded.
They are macro calls, so a build without treemacs in scope could not compile
them - and putting treemacs in scope would shadow the copy the user's Emacs
installs.  Everything they call is compiled; only this declaration is read.")

(defvar nitpick-tree--defined nil
  "Whether `nitpick-tree--definitions' has been evaluated.")

(defun nitpick-tree--define ()
  "Load treemacs and evaluate the node-type definitions, once.
`treemacs-treelib' by name: it holds the extension macros and nothing in
treemacs proper pulls it in."
  (unless nitpick-tree--defined
    (require 'treemacs)
    (require 'treemacs-treelib)
    (eval nitpick-tree--definitions t)
    (setq nitpick-tree--defined t)))

;;;; The pane

(defun nitpick-tree--display (buffer)
  "Show BUFFER in a side window on treemacs' own side, and return the window.
Slot 1, so the pane sits alongside a treemacs tree in slot 0 rather than
replacing it."
  (display-buffer-in-side-window
   buffer
   `((side . ,(if (boundp 'treemacs-position) treemacs-position 'left))
     (slot . 1)
     (window-width . ,(if (boundp 'treemacs-width) treemacs-width 40))
     (dedicated . t))))

;;;###autoload
(defun nitpick-tree (root revision)
  "Show the files that differ between REVISION and ROOT's worktree.

A side pane listing only those files, nested by directory, with each one's
status marker and line counts - and nothing else in the project, which is what
separates it from a file tree with git colours on it.  RET opens the real file,
where diff-hl is painting the same revision's changes.

REVISION defaults to the one this worktree last picked - through
`nitpick-diff-hl-set-base', or the PR a worktree was checked out for - so the
pane lists the files diff-hl is already painting.  A prefix argument asks for
another, and is also how the pane is pointed somewhere new.

Called again it re-renders, which is also the refresh: committing, staging or
unstaging redraws it, and nothing else does."
  (interactive
   ;; The pane's own root first: `default-directory' in a treemacs buffer is
   ;; whatever it was created with, so asking git there answers for the wrong
   ;; project, or for none.
   (let ((root (or nitpick-tree--root
                   (magit-toplevel)
                   (user-error "Not inside a git repository"))))
     (list root
           (let ((default-directory root)
                 (suggested (nitpick-diff-hl--suggested-base root)))
             (if (or current-prefix-arg (not suggested))
                 (magit-read-branch-or-commit "Tree of changes vs" suggested)
               suggested)))))
  (nitpick-tree--define)
  (let* ((files (nitpick-tree--changes root revision))
         (items (nitpick-tree--build files root))
         (stats (nitpick-tree--totals files))
         (existing (get-buffer nitpick-tree-buffer-name))
         ;; Where the pane was, so a refresh does not send point back to the
         ;; top of a review being read line by line.
         (line (and existing (with-current-buffer existing (line-number-at-pos))))
         (buffer (or existing (get-buffer-create nitpick-tree-buffer-name))))
    (with-current-buffer buffer
      (nitpick-tree--render root revision items stats))
    (let ((window (nitpick-tree--display buffer)))
      (when window
        (select-window window)
        (when line
          (goto-char (point-min))
          (forward-line (1- line)))))
    (when (called-interactively-p 'interactive)
      (message "%s" (nitpick-tree--header revision stats)))))

(defun nitpick-tree-refresh ()
  "Re-render the pane, if it is on screen, from what git says now.
On screen, not merely alive: re-rendering displays the pane, and a commit is
no reason to re-open one that was closed."
  (interactive)
  (let ((buffer (get-buffer nitpick-tree-buffer-name)))
    (when (and (buffer-live-p buffer) (get-buffer-window buffer t))
      (let ((root (buffer-local-value 'nitpick-tree--root buffer))
            (revision (buffer-local-value 'nitpick-tree--revision buffer)))
        (when (and root revision)
          (save-selected-window
            (nitpick-tree root revision)))))))

;; The pane is a snapshot of a diff, so it goes stale exactly when the diff
;; does.  Same events treemacs-magit watches for the same reason: git's own
;; index gives no notification.
(dolist (hook '(magit-post-commit-hook
                git-commit-post-finish-hook
                magit-post-stage-hook
                magit-post-unstage-hook))
  (add-hook hook #'nitpick-tree-refresh))

(provide 'nitpick-tree)

;;; nitpick-tree.el ends here
