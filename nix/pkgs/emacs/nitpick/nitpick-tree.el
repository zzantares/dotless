;;; nitpick-tree.el --- A treemacs pane of the files a review changed -*- lexical-binding: t; -*-

;; Author: dotless
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (magit "4.0") (treemacs "3.0"))
;; Keywords: vc, tools
;; URL: https://git.gutimore.net/gutimore/dotless

;;; Commentary:

;; A diff navigator: a side pane listing only the files that differ from the
;; revision under review, nested by directory with each file's status and line
;; counts, and the whole diff beside it.  Moving in the pane scrolls the diff to
;; the file - or to the subtree of a directory - so a review reads by walking the
;; pane, the way diffnav does it.  `o' opens the real file, where diff-hl has
;; already painted what the revision changed, and RET steps into the diff, where
;; magit's own keys and `nitpick-comment' work.
;;
;; One command, `nitpick-tree', which also refreshes the pane it opened.  The
;; revision is the one `nitpick-diff-hl-set-base' last picked for this worktree,
;; so the pane lists exactly the files diff-hl is painting; a prefix argument
;; asks for another.
;;
;; The diff is one magit buffer for the whole range, not one per file: the range
;; is a single `git diff', each file is a section in it, and a file is revealed
;; by scrolling to its section.  So following the point costs a `goto-char',
;; nothing is spawned per keystroke, and the diff stays continuous - the file
;; before and the file after are a scroll away, as they are in diffnav.
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
(declare-function treemacs-node-at-point "treemacs-core-utils" ())
(declare-function treemacs-expand-extension-node "treemacs-treelib" (&optional arg))
(declare-function treemacs-icon-for-file "treemacs-icons" (file))
(declare-function treemacs-icon-for-dir "treemacs-icons" (dir state))
(declare-function treemacs-collapse-extension-node "treemacs-treelib" (&optional arg))
(declare-function magit-diff-range "magit-diff" (rev-or-range &optional args files))
(declare-function magit-diff-arguments "magit-diff" (&optional mode))
(declare-function magit-section-show "magit-section" (section))
(declare-function diff-hl-mode "diff-hl" (&optional arg))
(declare-function diff-hl-update "diff-hl" ())
(declare-function diff-hl-next-hunk "diff-hl" (&optional backward))
(defvar diff-hl-mode)
(defvar diff-hl-update-async)
(defvar magit-display-buffer-function)
(defvar magit-display-buffer-noselect)
(defvar magit-git-debug)
(defvar magit-root-section)
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

(defcustom nitpick-tree-untracked-buffer-name "*nitpick-untracked*"
  "Name of the buffer an untracked file's additions are rendered in.
Not part of the range diff the pane navigates, so it cannot be a section of
it: `git diff' has no version of an untracked file to compare against."
  :type 'string
  :group 'nitpick)

(defcustom nitpick-tree-follow t
  "Whether moving in the pane scrolls the diff to the line at point.
What makes the pane a navigator rather than a list: the file under the point
is the file on screen, with no key pressed to ask for it.  Off, `d' is what
shows a diff, and `f' turns this back on."
  :type 'boolean
  :group 'nitpick)

(defcustom nitpick-tree-full-frame t
  "Whether opening the pane takes the frame, giving it back when it closes.
A review is a mode of its own, the way magit's status buffer is: the pane and
the diff it drives want the frame to themselves, and a layout of four other
windows has nowhere to put the diff.  The layout from before the review is
restored by `nitpick-tree-close'."
  :type 'boolean
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

(defcustom nitpick-tree-set-base t
  "Whether opening the pane also points diff-hl at the revision it lists.
Only when this worktree has no base yet, so an answer you gave stands.  With
it the pane and the files you open from it agree on the first keystroke:
without it the pane lists what the branch changed while the files still paint
their uncommitted edits, until `nitpick-diff-hl-set-base' is run too."
  :type 'boolean
  :group 'nitpick)

(defcustom nitpick-tree-paint-lines t
  "Whether the pane makes sure the files it opens show their changes.
`diff-hl-mode' in the file, so there is anything to see at all, and
`nitpick-diff-hl-line-mode' for whole-line backgrounds rather than fringe
marks alone, which is what a diff of any size wants.  The line mode is global,
the way the command that toggles it is - this only spares you running it."
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

(defvar nitpick-tree--painted nil
  "Whether the pane is what turned `nitpick-diff-hl-line-mode' on.
Closing undoes its own painting and nothing else: a mode turned on with the
command for it is the user's, and stays on.")

(defvar nitpick-tree--diff-buffer nil
  "The magit diff buffer the pane navigates, or nil.
One diff for one pane, re-read when the pane is, and scrolled rather than
re-run as the point moves.")

(defvar nitpick-tree--window-config nil
  "The frame's layout as it was before the pane took it, or nil.
Given back by `nitpick-tree-close'.")

(defvar-local nitpick-tree--root nil
  "Project root the pane was rendered for.")

(defvar-local nitpick-tree--revision nil
  "Revision, as picked, the pane lists the differences from.")

(defvar-local nitpick-tree--items nil
  "The pane's top-level nodes, as built by `nitpick-tree--build'.")

(defvar-local nitpick-tree--followed nil
  "Key of the node the diff was last scrolled to.
So that the several commands a keystroke runs reveal it once, and so that a
command which leaves the point where it was reveals nothing.")

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

(defun nitpick-tree--diff-hl-available-p ()
  "Whether diff-hl is there to be driven, loading it if it is not loaded yet."
  (or (featurep 'diff-hl) (require 'diff-hl nil t)))

(defun nitpick-tree--paint ()
  "Turn on whole-line painting, unless it is on or unwanted.
Nothing happens without diff-hl: the mode reads its highlight slots as it
starts, so it cannot run before diff-hl has defined them."
  (when (and nitpick-tree-paint-lines
             (not (bound-and-true-p nitpick-diff-hl-line-mode))
             (nitpick-tree--diff-hl-available-p))
    (nitpick-diff-hl-line-mode 1)
    (setq nitpick-tree--painted t)))

(defun nitpick-tree--unpaint ()
  "Turn whole-line painting back off, if the pane is what turned it on."
  (when nitpick-tree--painted
    (setq nitpick-tree--painted nil)
    (when (fboundp 'nitpick-diff-hl-line-mode)
      (nitpick-diff-hl-line-mode -1))))

(defun nitpick-tree--paint-buffer ()
  "Turn on `diff-hl-mode' in the current buffer if it is off.
Buffer-local, so a file opened from the pane shows its changes without
diff-hl being turned on everywhere on the pane\='s behalf."
  (when (and nitpick-tree-paint-lines
             (not (bound-and-true-p diff-hl-mode))
             (buffer-file-name)
             (fboundp 'diff-hl-mode))
    (diff-hl-mode 1)))

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

(defun nitpick-tree--visit-window (buffer)
  "Return the window NODE's BUFFER should be shown in, or nil for none.
The window already showing it, else the one last used - never a split, and
never the pane, which `get-mru-window' passes over as dedicated and as the
selected window.  `display-buffer' would split instead, because a side window
cannot show anything but the pane and it will make room rather than reuse."
  (or (get-buffer-window buffer)
      (get-mru-window (selected-frame) nil :not-selected)))

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
         (window (nitpick-tree--visit-window buffer)))
    ;; `switch-to-buffer' in that window rather than `set-window-buffer', so
    ;; the file lands in its history and `C-x left' works as it would have.
    (if window
        (with-selected-window window (switch-to-buffer buffer))
      ;; The pane is the only window: there is nothing to reuse yet.
      (setq window (display-buffer buffer)))
    (when (and window (not stay))
      (select-window window)
      (nitpick-tree--paint-buffer)
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

;;;; The diff the pane drives

(defun nitpick-tree--main-window ()
  "Return the window on this frame the diff belongs in, or nil.
Never a side window: the pane is in one, and a side window shows nothing but
what it was made for.  The last used one, so the diff and the files opened
from the pane land in the same place."
  (let ((mru (get-mru-window (selected-frame) nil :not-selected)))
    (if (and mru (not (window-parameter mru 'window-side)))
        mru
      (seq-find (lambda (window) (not (window-parameter window 'window-side)))
                (window-list nil 'nomini)))))

(defun nitpick-tree--display-diff (buffer)
  "Show BUFFER in this frame's main window and return that window.
What magit's display function is replaced with while the diff is read: magit
would split the window the pane opens files in, or take the frame, and the
review's layout is the pane and the diff beside it."
  (let ((window (nitpick-tree--main-window)))
    (if window
        (progn (set-window-buffer window buffer) window)
      (display-buffer buffer))))

(defun nitpick-tree--build-diff (root revision)
  "Read ROOT's whole diff against REVISION into a magit buffer.
The range, not a file of it: the pane reveals a file by scrolling to its
section, so there is one `git diff' per review rather than one per keystroke.
The user's diff arguments are kept, their last diff's pathspec is not - see
`nitpick-diff-show'.

Returned, and remembered as the pane's diff.  Magit's display function and
its focus are taken over for the call: the diff goes in the main window, and
the point stays in the pane."
  (let* ((default-directory root)
         (base (or (nitpick--base-revision revision)
                   (user-error "Cannot work out a merge base for %s" revision)))
         (magit-display-buffer-function #'nitpick-tree--display-diff)
         (magit-display-buffer-noselect t)
         (buffer (magit-diff-range base (car (magit-diff-arguments)) nil)))
    (unless (bufferp buffer)
      (error "Magit returned no diff buffer for %s" base))
    (setq nitpick-tree--diff-buffer buffer)))

(defun nitpick-tree--ensure-diff (root revision)
  "Return the pane's diff buffer, reading it first if it is not there."
  (if (buffer-live-p nitpick-tree--diff-buffer)
      nitpick-tree--diff-buffer
    (nitpick-tree--build-diff root revision)))

(defun nitpick-tree--diff-on-screen-p ()
  "Whether the pane's diff is in a window on this frame."
  (and (buffer-live-p nitpick-tree--diff-buffer)
       (get-buffer-window nitpick-tree--diff-buffer)
       t))

(defun nitpick-tree--show (buffer)
  "Make sure BUFFER is on screen, and return the window showing it.
Where it already is, else the main window - which is how the diff comes back
after `o' put a file there."
  (or (get-buffer-window buffer)
      (nitpick-tree--display-diff buffer)))

(defun nitpick-tree--find-section (buffer node root)
  "Return the section of BUFFER where NODE's changes start, or nil.
A file is the section whose value is its path - for a rename that is the new
name, which is the one the pane lists.  A directory is the first section
under it: git orders a diff by path, so a subtree is contiguous and its top
is where reading it begins.

Only the diff's own file sections are looked at, never the diffstat's: those
are children of the diffstat section, not of the root."
  (let* ((dir (plist-get node :dir))
         (want (if dir
                   (file-name-as-directory
                    (file-relative-name (plist-get node :path) root))
                 (plist-get node :file))))
    (with-current-buffer buffer
      (seq-find
       (lambda (section)
         (and (eq (nitpick--oref section 'type) 'file)
              (let ((value (nitpick--oref section 'value)))
                (and (stringp value)
                     (if dir
                         (string-prefix-p want value)
                       (equal want value))))))
       (and magit-root-section
            (nitpick--oref magit-root-section 'children))))))

(defun nitpick-tree--untracked-diff (file root)
  "Return a buffer showing untracked FILE under ROOT as added lines.
`git diff --no-index' against `/dev/null', in `diff-mode' rather than as a
magit section: git holds no version of the file, so it is in no range diff -
but a file a review forgot to add is the one most worth reading."
  (let* ((default-directory root)
         ;; --no-index exits non-zero whenever the two files differ, which is
         ;; every time; `magit-git-debug' would report that as a failure.
         (magit-git-debug nil)
         (text (nitpick-tree--git-output "diff" "--no-index" "--" "/dev/null" file))
         (buffer (get-buffer-create nitpick-tree-untracked-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        ;; An empty file differs from /dev/null in nothing at all.
        (insert (if (string-empty-p text) (format "%s is empty\n" file) text))
        (diff-mode)
        (setq-local default-directory root
                    header-line-format (concat " " file "  untracked"))
        (setq buffer-read-only t)
        (goto-char (point-min))))
    buffer))

(defun nitpick-tree--reveal-untracked (node root select)
  "Show NODE's untracked file on screen, selecting it when SELECT.
Returns the window it went in."
  (let* ((buffer (nitpick-tree--untracked-diff (plist-get node :file) root))
         (window (nitpick-tree--show buffer)))
    (when (and window select)
      (select-window window))
    window))

(defun nitpick-tree--reveal (node &optional select)
  "Scroll the pane's diff to NODE's changes, and return its window.
The diff is read if it has not been, and put back on screen if something
else took the window.  The section is expanded first - magit draws a deleted
file collapsed - and left at the top of the window, so what is on screen
begins where the file does.

With SELECT the diff window is selected, which is RET: the pane hands the
point over and magit's own keys take it from there."
  (let ((root nitpick-tree--root)
        (revision nitpick-tree--revision))
    (if (equal (plist-get node :status) "?")
        (nitpick-tree--reveal-untracked node root select)
      (let* ((buffer (nitpick-tree--ensure-diff root revision))
             (section (nitpick-tree--find-section buffer node root))
             (window (nitpick-tree--show buffer)))
        (cond
         ((and window section)
          (with-selected-window window
            (magit-section-show section)
            (goto-char (nitpick--oref section 'start))
            (recenter 0)))
         ((null section)
          (message "%s: not in the diff - `r' re-reads it"
                   (or (plist-get node :file) (plist-get node :name)))))
        (when (and window select)
          (select-window window))
        window))))

(defun nitpick-tree--follow ()
  "Reveal the node the point has moved onto, once per node.
On `post-command-hook' in the pane, where the navigation keys are: revealing
is a `goto-char' in a buffer already read, so there is nothing to debounce.
A `user-error' is swallowed - a file whose diff cannot be shown must not
break every keystroke in the pane."
  (when nitpick-tree-follow
    (let* ((node (nitpick-tree--node-at-point))
           (key (plist-get node :path)))
      (unless (equal key nitpick-tree--followed)
        (setq nitpick-tree--followed key)
        (when node
          (ignore-error user-error
            (nitpick-tree--reveal node)))))))

(defun nitpick-tree-toggle-follow ()
  "Turn the diff that follows the point in the pane on or off.
Off, the pane is a list of files and `d' is what shows a diff of one."
  (interactive)
  (setq nitpick-tree-follow (not nitpick-tree-follow)
        nitpick-tree--followed nil)
  (when nitpick-tree-follow
    (nitpick-tree--follow))
  (message "nitpick-tree: follow %s" (if nitpick-tree-follow "on" "off")))

(defun nitpick-tree-visit-diff (&optional stay)
  "Show the changes of the line at point in the pane's diff.

The reading view of the same change `nitpick-tree-visit' opens the file for:
removed lines are text, unchanged context is folded away.  On a directory it
is everything under it.  What following the point does on its own - this is
how to ask for it with `nitpick-tree-follow' off.

With a prefix argument STAY the diff is shown but the pane keeps the point."
  (interactive "P")
  (let ((node (nitpick-tree--node-at-point)))
    (when node
      (setq nitpick-tree--followed (plist-get node :path))
      (nitpick-tree--reveal node (not stay)))))

(defun nitpick-tree-ret (&optional arg)
  "Step into the diff of the file at point, or fold the directory on it.
A directory expands or collapses, as everywhere in treemacs.  A file hands
the point to the diff window, where magit's keys read it and
`nitpick-comment' comments on it; `o' is what opens the file itself.  ARG is
treemacs' prefix argument for a directory."
  (interactive "P")
  (let ((node (nitpick-tree--node-at-point)))
    (if (and node (not (plist-get node :dir)))
        (nitpick-tree-visit-diff)
      (nitpick-tree-visit arg))))

(defvar nitpick-tree-mode-map
  (let ((map (make-sparse-keymap)))
    ;; `d' is `treemacs-delete-file' in `treemacs-mode-map', and dead under
    ;; evil, whose motion state suppresses plain letters.  Shadowing it is
    ;; wanted either way: `d' reads a diff everywhere else, and deleting a
    ;; file out of a review pane is no accident to invite.
    (define-key map "d" #'nitpick-tree-visit-diff)
    ;; `o' is treemacs' prefix for opening a node in a split, which is the one
    ;; thing a review does not want: the diff is in the other window and
    ;; splitting it is how the old pane made reading one tiring.
    (define-key map "o" #'nitpick-tree-visit)
    (define-key map "f" #'nitpick-tree-toggle-follow)
    ;; `g' and `r' are `treemacs-refresh', which redraws the nodes the pane
    ;; already holds, reports "Refresh complete" and asks git nothing.  The
    ;; pane is a snapshot, so its refresh has to re-read the diff.
    (define-key map "g" #'nitpick-tree-refresh)
    (define-key map "r" #'nitpick-tree-refresh)
    ;; `q' is `treemacs-quit', which buries the pane and leaves the painting
    ;; on: the two ways of closing should not differ.
    (define-key map "q" #'nitpick-tree-close)
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
       :ret-action #'nitpick-tree-ret)

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
                               nitpick-tree--followed nil
                               treemacs-space-between-root-nodes nil
                               header-line-format (nitpick-tree--header revision stats))
                   ;; Buffer-local, and re-added on every render: the locals
                   ;; and the hooks both go when `treemacs-mode' restarts.
                   (add-hook 'post-command-hook #'nitpick-tree--follow nil t)
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

(defun nitpick-tree--window ()
  "Return the window showing the pane on this frame, or nil.
This frame only: the key is asking about the frame it was pressed on, and a
pane left open on another one is not in the way here."
  (let ((buffer (get-buffer nitpick-tree-buffer-name)))
    (and buffer (get-buffer-window buffer))))

(defun nitpick-tree--take-frame ()
  "Save this frame's layout and leave one window for the diff.
A review takes the frame the way magit's status buffer does: what the pane
drives is the diff beside it, and a layout of four other windows has nowhere
to put that.  Given back by `nitpick-tree-close'.

Nothing is saved while the pane is up - the layout to give back is the one
from before the review, not the review's own - and nothing is deleted from
inside a side window, where it is an error."
  (when (and nitpick-tree-full-frame (not (nitpick-tree--window)))
    (setq nitpick-tree--window-config (current-window-configuration))
    (let ((window (nitpick-tree--main-window)))
      (when window
        (select-window window)))
    (unless (window-parameter (selected-window) 'window-side)
      (delete-other-windows))))

(defun nitpick-tree--give-frame-back ()
  "Put back the layout `nitpick-tree--take-frame' saved, if it saved one."
  (when nitpick-tree--window-config
    (let ((config nitpick-tree--window-config))
      (setq nitpick-tree--window-config nil)
      (set-window-configuration config))))

(defun nitpick-tree-close ()
  "Close the pane, undo its painting and give the frame back.
The buffer goes with the window: it holds a diff read once, and opening again
reads a fresh one.  A base set along the way stays - that is the revision
being reviewed rather than a way of drawing it, and
`nitpick-diff-hl-set-base' is what changes it.

The magit diff buffer stays too, the way magit's own buffers do; it is only
forgotten, so the next review reads its own range."
  (interactive)
  (let ((buffer (get-buffer nitpick-tree-buffer-name))
        (untracked (get-buffer nitpick-tree-untracked-buffer-name)))
    (dolist (window (and buffer (get-buffer-window-list buffer nil t)))
      (when (window-live-p window)
        (delete-window window)))
    (nitpick-tree--unpaint)
    (setq nitpick-tree--diff-buffer nil)
    (when (buffer-live-p buffer)
      (kill-buffer buffer))
    (when (buffer-live-p untracked)
      (kill-buffer untracked))
    (nitpick-tree--give-frame-back)))

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
  "Review what REVISION and ROOT's worktree differ by, file by file.

A side pane listing only those files, nested by directory, with each one's
status marker and line counts - and nothing else in the project, which is what
separates it from a file tree with git colours on it - and the diff of the
range beside it.  Moving in the pane scrolls the diff to the file at point, or
to the subtree of the directory at point, so the review reads by walking the
pane.

RET hands the point to the diff, where magit's keys read it and
`nitpick-comment' comments on it.  `o' opens the real file, where diff-hl is
painting the same revision's changes.  `d' reveals a diff that `f' stopped
following, and `q' closes the pane and gives the frame back.

REVISION defaults to the one this worktree last picked - through
`nitpick-diff-hl-set-base', or the PR a worktree was checked out for - and
failing that to the nearest ancestor branch, worked out from the commit graph.
A prefix argument asks for another, and is also how the pane is pointed
somewhere new.

Unless `nitpick-tree-set-base' says otherwise, a worktree with no base yet
gets pointed at REVISION, so the files opened from the pane paint the same
changes the pane lists.  A base already picked is left alone.  And unless
`nitpick-tree-paint-lines' says otherwise, those changes are painted as whole
lines rather than fringe marks alone.

Called with the pane already open it closes it again, undoing the painting it
turned on.  A prefix argument always opens, so it is also how an open pane is
pointed somewhere new.  `r' in the pane re-reads the diff, as does
committing, staging or unstaging."
  (interactive
   ;; Closing works nothing out: there is no revision to suggest and nothing
   ;; to ask the forge for.  A prefix argument always means open.
   (if (and (null current-prefix-arg) (nitpick-tree--window))
       (list nil nil)
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
                 suggested))))))
  (if (and (null root) (null revision))
      (nitpick-tree-close)
    (nitpick-tree--open root revision)))

(defun nitpick-tree--open (root revision)
  "Render ROOT's differences from REVISION in the pane, and select it.
The diff beside it is read on a fresh opening, and re-read by a refresh that
finds it on screen.  Not by one that does not: a refresh runs on every commit
and every staging, and pushing a diff in front of the magit buffer the user is
committing from is not a redraw of the pane."
  (nitpick-tree--define)
  (nitpick-tree--paint)
  ;; Before reading the diff: this also caches the revision, which is what
  ;; stops a second opening from setting it again over an answer since given.
  (when (and nitpick-tree-set-base
             (not (alist-get (nitpick-diff-hl--root root) nitpick-diff-hl--bases
                             nil nil #'string-equal)))
    (nitpick-diff-hl-set-base root revision))
  (let* ((fresh (not (nitpick-tree--window)))
         (diff (or fresh (nitpick-tree--diff-on-screen-p)))
         (files (nitpick-tree--changes root revision))
         (items (nitpick-tree--build files root))
         (stats (nitpick-tree--totals files))
         (existing (get-buffer nitpick-tree-buffer-name))
         ;; Where the pane was, so a refresh does not send point back to the
         ;; top of a review being read line by line.
         (line (and existing (with-current-buffer existing (line-number-at-pos))))
         (buffer (or existing (get-buffer-create nitpick-tree-buffer-name))))
    (nitpick-tree--take-frame)
    (with-current-buffer buffer
      (nitpick-tree--render root revision items stats))
    (let ((window (nitpick-tree--display buffer)))
      ;; The diff after the pane: the pane's side window is the one window
      ;; `nitpick-tree--main-window' has to pass over.
      (when diff
        (nitpick-tree--build-diff root revision))
      (when window
        (select-window window)
        (when line
          (goto-char (point-min))
          (forward-line (1- line)))
        ;; Explicitly, rather than waiting for the hook: a refresh driven by
        ;; a magit hook ends with the point somewhere else entirely.  And only
        ;; where the diff was re-read, for the same reason it was not.
        (when diff
          (nitpick-tree--follow))))
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
