;;; nitpick-tree.el --- A treemacs pane of the files a review changed -*- lexical-binding: t; -*-

;; Author: dotless
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (magit "4.0") (treemacs "3.0"))
;; Keywords: vc, tools
;; URL: https://git.gutimore.net/gutimore/dotless

;;; Commentary:

;; A diff navigator: a side pane listing only the files that differ from the
;; revision under review, nested by directory with each file's status and line
;; counts, and the diff beside it - narrowed to what the line at point covers, a
;; file's own diff or a directory's whole subtree, the way diffnav draws them.
;; So a review reads by walking the pane; `N' gives the whole range back.  `o'
;; opens the real file, where diff-hl has already painted what the revision
;; changed, and RET steps into the diff, where magit's own keys and
;; `nitpick-comment' work.
;;
;; One command, `nitpick-tree', which also refreshes the pane it opened.  The
;; revision is the one `nitpick-diff-hl-set-base' last picked for this worktree,
;; so the pane lists exactly the files diff-hl is painting; a prefix argument
;; asks for another.
;;
;; The diff is one magit buffer for the whole range, not one per file: the range
;; is a single `git diff', each file is a section in it, and a node is revealed
;; by narrowing to the span of its sections - which git's ordering by path makes
;; one run.  So following the point costs a `narrow-to-region' and nothing is
;; spawned per keystroke, where diffnav re-serializes the subtree's parsed patch
;; and runs delta over it again.  Widened, the same buffer reads continuously:
;; the file before and the file after are a scroll away.
;;
;; The pane can also be driven by a patch rather than by a revision, which is
;; what `nitpick-pr' opens a pull request with: same sections, same keys, no
;; checkout.  A patch has no files, so the first `o' hands over - the patch
;; carries what to run to materialise one - and the pane is re-read from git
;; there.
;;
;; `nitpick-tree-range' drives it from two revisions, for reading work that is
;; not yours without moving your own worktree.  Both sides are in git already,
;; so `o' opens them as blobs rather than checking anything out.
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
(declare-function magit-diff-read-range-or-commit "magit-diff" (prompt &optional secondary-default mbase))
(declare-function magit-split-range "magit-git" (range &optional abbrev))
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
(declare-function nitpick-tree--render "nitpick-tree"
                  (root revision items stats &optional patch))

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

(defcustom nitpick-tree-narrow t
  "Whether the diff shows only what the line at point covers.
A file reads as its own diff and a directory as the diff of its subtree, the
way diffnav draws them.  Off, the diff is the whole range scrolled to that
file, so the file before and the file after are a scroll away; `N' switches."
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

(defvar-local nitpick-tree--patch nil
  "The patch the pane was rendered from, or nil when git is its source.
A plist: `:label' for the header line, `:root' the absolute prefix its paths
are keyed by, `:diff' a function returning the washed diff buffer, and
`:check-out' one that materialises a worktree, called with the file being
opened and a callback handed that worktree's path.")

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

;;;; Reading the diff out of a patch

(defun nitpick-tree--sides ()
  "Return the (OLD . NEW) revisions the pane compares, or nil.
Nil is the ordinary pane, whose new side is the worktree."
  (and nitpick-tree--patch (plist-get nitpick-tree--patch :sides)))

(defun nitpick-tree--patch-status (header source)
  "Return git's status letter for a file section with HEADER and SOURCE.
HEADER is the raw diff header magit kept, SOURCE the name a rename came from."
  (cond ((and header (string-match-p "^new file" header)) "A")
        ((and header (string-match-p "^deleted file" header)) "D")
        (source "R")
        (t "M")))

(defun nitpick-tree--count-changed (beg end)
  "Return (ADDED . DELETED), counting the changed lines between BEG and END.
The headers are not in the buffer - magit keeps them in the section - so
every `+' and `-' line between the two is a changed line."
  (let ((added 0)
        (deleted 0))
    (save-excursion
      (goto-char beg)
      (while (< (point) end)
        (pcase (char-after)
          (?+ (setq added (1+ added)))
          (?- (setq deleted (1+ deleted))))
        (forward-line 1)))
    (cons added deleted)))

(defun nitpick-tree--diff-changes (buffer)
  "Return a plist per file in BUFFER's washed diff.
What `nitpick-tree--changes' returns for a revision, read back out of the
diff instead: a patch has no revision to ask git about, and the pane and the
diff cannot then disagree about what it holds."
  (with-current-buffer buffer
    (save-restriction
      (widen)
      (mapcar
       (lambda (section)
         (let* ((source (nitpick--oref section 'source))
                (binary (nitpick--oref section 'binary))
                (counts (and (not binary)
                             (nitpick-tree--count-changed
                              (nitpick--oref section 'start)
                              (nitpick--oref section 'end)))))
           (list :file (nitpick--oref section 'value)
                 :status (nitpick-tree--patch-status
                          (nitpick--oref section 'header) source)
                 :from source
                 :added (car counts)
                 :deleted (cdr counts)
                 :binary (and binary t))))
       (nitpick-tree--file-sections buffer)))))

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

(defun nitpick-tree--header (revision totals &optional patch)
  "Return the pane's header line for REVISION and TOTALS.
A pane read from PATCH names the patch instead, and does not say `vs': what
the forge diffed it against is not something git here can resolve."
  (let ((count (nth 0 totals)))
    (concat (if patch
                (concat " " (propertize (plist-get patch :label)
                                        'face 'nitpick-tree-revision))
              (concat " vs " (propertize revision 'face 'nitpick-tree-revision)))
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

(defun nitpick-tree--node-side (node)
  "Return the version NODE's file belongs to.
A deleted file is in the base and nowhere else.  Everything else - modified,
added, untracked - is in the worktree, the same way a context line resolves
to the file you edit."
  (if (equal (plist-get node :status) "D") 'old 'new))

(defun nitpick-tree--node-target (node side)
  "Return (REV FILE) naming the version SIDE holds of NODE's file.
A rename is asked for by the name the side itself used.  The new side is the
worktree, unless the pane compares two revisions, where it is the newer of
the two - neither of them is checked out."
  (let ((sides (nitpick-tree--sides)))
    (pcase side
      ('old (list (if sides
                      (car sides)
                    (nitpick--base-revision nitpick-tree--revision))
                  (or (plist-get node :from) (plist-get node :file))))
      (_ (list (if sides (cdr sides) "{worktree}")
               (plist-get node :file))))))

(defun nitpick-tree--node-line (node side)
  "Return the line NODE's first change starts at on SIDE, or nil.

Asked of the diff the pane already holds, so opening a revision runs no
second `git diff' - and asked through `nitpick--visit-line', so the pane
lands where `nitpick-visit-other' lands from that file's heading: on the
change itself rather than on the first line of context above it."
  (and (buffer-live-p nitpick-tree--diff-buffer)
       (and-let* ((root nitpick-tree--root)
                  (section (car (nitpick-tree--node-sections
                                 (nitpick-tree--file-sections
                                  nitpick-tree--diff-buffer)
                                 node root))))
         (with-current-buffer nitpick-tree--diff-buffer
           (save-excursion
             ;; Widened: the diff is narrowed to the node the point is on, and
             ;; the file being opened need not be that one.
             (save-restriction
               (widen)
               (goto-char (nitpick--oref section 'start))
               (nitpick--visit-line side)))))))

(defun nitpick-tree--visit-node (node side)
  "Open NODE's file as SIDE holds it, and select the window it lands in.
A side the file has no version in opens the side it has, and says so - the
pane's half of the rule `nitpick-visit' follows in a diff."
  (let* ((root nitpick-tree--root)
         (default-directory root)
         (asked side)
         (note nil))
    (pcase-let ((`(,rev ,file) (nitpick-tree--node-target node side)))
      (unless (nitpick--visit-exists-p rev file)
        (setq side (nitpick--visit-complement side))
        (pcase-setq `(,rev ,file) (nitpick-tree--node-target node side))
        (unless (nitpick--visit-exists-p rev file)
          (user-error "No version of %s to open" (plist-get node :file)))
        (setq note (nitpick--visit-note asked side rev)))
      ;; Worked out while the pane is still the current buffer, and once the
      ;; side is settled: the revision, the root and the diff are its locals.
      (let* ((line (nitpick-tree--node-line node side))
             (buffer (if (equal rev "{worktree}")
                         (find-file-noselect (expand-file-name file root))
                       (magit-find-file-noselect rev file)))
             (window (nitpick-tree--visit-window buffer)))
        ;; `switch-to-buffer' in that window rather than `set-window-buffer', so
        ;; the file lands in its history and `C-x left' works as it would have.
        (if window
            (with-selected-window window (switch-to-buffer buffer))
          ;; The pane is the only window: there is nothing to reuse yet.
          (setq window (display-buffer buffer)))
        (when window
          (select-window window)
          (if (equal rev "{worktree}")
              (progn (nitpick-tree--paint-buffer)
                     (nitpick-tree--show-hunk))
            (when (and line nitpick-tree-visit-jumps-to-hunk)
              (goto-char (point-min))
              (forward-line (1- line)))))
        (when note
          (message "%s: %s" file note))
        buffer))))

(defun nitpick-tree--goto-file (file)
  "Put point on the pane's line for FILE, and return it, or nil.
The pane is drawn fully expanded, so the line is there to be found."
  (goto-char (point-min))
  (let (found)
    (while (and (not found) (not (eobp)))
      (let ((node (nitpick-tree--node-at-point)))
        (if (equal (and node (plist-get node :file)) file)
            (setq found (point))
          (forward-line 1))))
    found))

(defun nitpick-tree--goto-node ()
  "Put point on the pane's first node, unless it is on one already.
treemacs draws a line above the first node that no node owns, and the point
starts there - where the diff has nothing to follow until a key is pressed."
  (unless (nitpick-tree--node-at-point)
    (goto-char (point-min))
    (while (and (not (nitpick-tree--node-at-point)) (not (eobp)))
      (forward-line 1))))

(defun nitpick-tree--adopt (root file)
  "Re-read the pane from git in ROOT, and open FILE from it.
Where a patch's `:check-out' lands: the worktree it made is a checkout like
any other, so the pane it gets is the git one - real files on both sides,
diff-hl painting them, `nitpick-comment' able to anchor a thread - and the
file the hand-off started from is the one it ends on."
  (setq nitpick-tree--diff-buffer nil)
  (let ((revision (let ((default-directory root))
                    (or (nitpick-diff-hl--suggested-base root)
                        (user-error "Cannot work out what to diff %s against" root)))))
    (nitpick-tree--open root revision)
    (let ((buffer (get-buffer nitpick-tree-buffer-name)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (if (nitpick-tree--goto-file file)
              (nitpick-tree-visit)
            (message "%s is not in the diff of %s" file revision)))))))

(defun nitpick-tree--check-out (node)
  "Have the patch checked out, and open NODE's file once it is.
A pane read from a patch has no files to open; `:check-out' is what fetches
them, and it runs asynchronously, so the pane stays usable until it lands.
The file goes with the callback: what is being waited for is worth saying
while the waiting happens."
  (let ((patch nitpick-tree--patch)
        (file (or (and node (plist-get node :file))
                  (user-error "No file here"))))
    (funcall (or (plist-get patch :check-out)
                 (user-error "This patch cannot be checked out"))
             file
             (lambda (root) (nitpick-tree--adopt root file)))))

(defun nitpick-tree--checks-out-p ()
  "Whether the pane has to be checked out before a file can be opened.
A patch holds no files.  Two revisions hold both sides already, so those are
opened as blobs instead."
  (and nitpick-tree--patch (not (nitpick-tree--sides))))

(defun nitpick-tree--open-file (node side)
  "Open NODE's file as SIDE holds it, checking the patch out first if need be."
  (if (nitpick-tree--checks-out-p)
      (nitpick-tree--check-out node)
    (nitpick-tree--visit-node node side)))

(defun nitpick-tree-visit (&optional arg)
  "Open the file on the current line, or fold the directory on it.

The version the line belongs to: the worktree for a file this review changed
or added, the base for one it deleted - the pane's own half of the rule
`nitpick-visit' follows in the diff.  `nitpick-tree-visit-other' is the other
side.

With a prefix ARG, pick the version by name.  On a directory ARG is
treemacs', which has nothing to open."
  (interactive "P")
  (let ((node (nitpick-tree--node-at-point)))
    (cond
     ((null node) nil)
     ((plist-get node :dir)
      (if (memq (get-text-property (treemacs-node-at-point) :state)
                treemacs--open-node-states)
          (treemacs-collapse-extension-node arg)
        (treemacs-expand-extension-node arg)))
     (arg (nitpick-tree-visit-pick))
     (t (nitpick-tree--open-file node (nitpick-tree--node-side node))))))

(defun nitpick-tree-visit-other (&optional arg)
  "Open the file on the current line as the other version holds it.
The base for a file the review changed or added, the worktree for one it
deleted.  With a prefix ARG, pick the version by name."
  (interactive "P")
  (let ((node (nitpick-tree--node-at-point)))
    (when (and node (not (plist-get node :dir)))
      (if arg
          (nitpick-tree-visit-pick)
        (nitpick-tree--open-file
         node (nitpick--visit-complement (nitpick-tree--node-side node)))))))

(defun nitpick-tree-visit-pick ()
  "Open the file on the current line as a version picked by name.
Nothing to pick from a patch: both sides arrive with the checkout, so that is
what this asks for there."
  (interactive)
  (let ((node (or (nitpick-tree--node-at-point) (user-error "No file here"))))
    (if (nitpick-tree--checks-out-p)
        (nitpick-tree--check-out node)
      (let* ((default-directory nitpick-tree--root)
             (sides (nitpick-tree--sides))
             (candidates
              (seq-filter
               (lambda (candidate)
                 (pcase-let ((`(,rev ,file) (nitpick-tree--node-target
                                             node (cdr candidate))))
                   (nitpick--visit-exists-p rev file)))
               (list (cons (if sides (cdr sides) "worktree") 'new)
                     (cons (if sides (car sides) "base") 'old))))
             (label (completing-read "Open this file as: " candidates nil t)))
        (nitpick-tree--visit-node node (cdr (assoc label candidates)))))))

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

(defun nitpick-tree--patch-diff (patch)
  "Return the diff buffer PATCH is washed into, remembered as the pane's.
Built, not displayed: where the diff goes is the pane's business."
  (setq nitpick-tree--diff-buffer (funcall (plist-get patch :diff))))

(defun nitpick-tree--range-diff (root range)
  "Read ROOT's diff for RANGE into a magit buffer, and return it.
RANGE as written, so git resolves `...' itself; the window and the focus are
taken over the way `nitpick-tree--build-diff' takes them."
  (let* ((default-directory root)
         (magit-display-buffer-function #'nitpick-tree--display-diff)
         (magit-display-buffer-noselect t)
         (buffer (magit-diff-range range (car (magit-diff-arguments)) nil)))
    (unless (bufferp buffer)
      (error "Magit returned no diff buffer for %s" range))
    buffer))

(defun nitpick-tree--range-source (root range sides)
  "Return what the pane needs to drive the diff of RANGE in ROOT.
SIDES is the (OLD . NEW) revisions it compares, as `magit-split-range'
resolves them - a three-dot range names its merge base.  No `:check-out':
git holds both sides already, so `o' opens them as blobs."
  (list :label range
        :sides sides
        :diff (lambda () (nitpick-tree--range-diff root range))))

(defun nitpick-tree--ensure-diff (root revision)
  "Return the pane's diff buffer, reading it first if it is not there."
  (cond ((buffer-live-p nitpick-tree--diff-buffer) nitpick-tree--diff-buffer)
        (nitpick-tree--patch (nitpick-tree--patch-diff nitpick-tree--patch))
        (t (nitpick-tree--build-diff root revision))))

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

(defun nitpick-tree--file-sections (buffer)
  "Return BUFFER's own file sections, in the order the diff wrote them.
The diff's own, never the diffstat's: those name the same files and are
children of the diffstat section rather than of the root."
  (with-current-buffer buffer
    (seq-filter
     (lambda (section)
       (and (eq (nitpick--oref section 'type) 'file)
            (stringp (nitpick--oref section 'value))))
     (and magit-root-section
          (nitpick--oref magit-root-section 'children)))))

(defun nitpick-tree--node-sections (all node root)
  "Return the sections of ALL that NODE's changes are in, in diff order.
A file is the one section whose value is its path - for a rename that is the
new name, which is the one the pane lists.  A directory is every section
under it.  Empty when the diff holds none: a pane read before the last commit
lists files the diff no longer has."
  (let* ((dir (plist-get node :dir))
         (want (if dir
                   (file-name-as-directory
                    (file-relative-name (plist-get node :path) root))
                 (plist-get node :file))))
    (seq-filter
     (lambda (section)
       (let ((value (nitpick--oref section 'value)))
         (if dir (string-prefix-p want value) (equal want value))))
     all)))

(defun nitpick-tree--contiguous-p (all sections)
  "Whether SECTIONS are a run of ALL with nothing of ALL between them.
What narrowing needs, and what git's own ordering by path gives a subtree -
but rename detection can place a file outside its directory's run, and Emacs
cannot narrow around a hole."
  (let ((from (seq-position all (car sections) #'eq))
        (to (seq-position all (car (last sections)) #'eq)))
    (and from to (= (length sections) (1+ (- to from))))))

(defun nitpick-tree--scope (sections narrow)
  "Put the first of SECTIONS at the top of the current window.
With NARROW the window shows nothing but SECTIONS: the diff is narrowed to
the span they cover, which for a directory is its subtree alone.  Expanded
first either way - magit draws a deleted file collapsed, and that is a file a
review has to read."
  (widen)
  (if narrow
      (progn (mapc #'magit-section-show sections)
             (narrow-to-region (nitpick--oref (car sections) 'start)
                               (nitpick--oref (car (last sections)) 'end)))
    (magit-section-show (car sections)))
  (goto-char (nitpick--oref (car sections) 'start))
  (recenter 0))

(defun nitpick-tree--widen ()
  "Give the pane's diff its whole range back, if it is narrowed to a node."
  (when (buffer-live-p nitpick-tree--diff-buffer)
    (with-current-buffer nitpick-tree--diff-buffer
      (widen))))

(defvar-local nitpick-tree--untracked-file nil
  "Absolute name of the untracked file the preview shows.")

(defun nitpick-tree-untracked-visit ()
  "Open the untracked file this buffer shows.
Both keys do it: git holds no other version of it, so there is no other side
for `nitpick-visit-other' to mean."
  (interactive)
  (let ((file nitpick-tree--untracked-file))
    (unless file
      (user-error "Not showing an untracked file"))
    (pop-to-buffer-same-window (find-file-noselect file))))

(defvar nitpick-tree-untracked-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'nitpick-tree-untracked-visit)
    (define-key map (kbd "S-<return>") #'nitpick-tree-untracked-visit)
    map)
  "Keymap of the untracked preview, composed over `diff-mode-map'.")

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
        (use-local-map (make-composed-keymap nitpick-tree-untracked-mode-map
                                             (current-local-map)))
        (setq-local default-directory root
                    nitpick-tree--untracked-file (expand-file-name file root)
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
  "Show NODE's changes in the pane's diff, and return its window.
The diff is read if it has not been, and put back on screen if something
else took the window.  Unless `nitpick-tree-narrow' says otherwise it is
narrowed to NODE - a file to its own diff, a directory to its subtree;
otherwise the whole range stays, scrolled so NODE is at the top.

A subtree the diff holds out of order is scrolled to rather than narrowed:
Emacs narrows to one region, and a hole in that region would hide a file the
review has to read.

With SELECT the diff window is selected, which is RET: the pane hands the
point over and magit's own keys take it from there."
  (let ((root nitpick-tree--root)
        (revision nitpick-tree--revision))
    (if (equal (plist-get node :status) "?")
        (nitpick-tree--reveal-untracked node root select)
      (let* ((buffer (nitpick-tree--ensure-diff root revision))
             (all (nitpick-tree--file-sections buffer))
             (sections (nitpick-tree--node-sections all node root))
             (window (nitpick-tree--show buffer)))
        (cond
         ((and window sections)
          (with-selected-window window
            (nitpick-tree--scope
             sections
             (and nitpick-tree-narrow
                  (nitpick-tree--contiguous-p all sections)))))
         ((null sections)
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

(defun nitpick-tree-toggle-narrow ()
  "Narrow the diff to the line at point, or give it the whole range back.
Narrowed, a directory reads as the diff of its subtree and a file as its own.
Widened, the diff is the whole range scrolled to that file, so the file
before and the file after are one scroll away."
  (interactive)
  (setq nitpick-tree-narrow (not nitpick-tree-narrow)
        nitpick-tree--followed nil)
  (nitpick-tree--widen)
  (nitpick-tree--follow)
  (message "nitpick-tree: narrow %s" (if nitpick-tree-narrow "on" "off")))

(defun nitpick-tree-visit-diff (&optional stay)
  "Show the changes of the line at point in the pane's diff.

The reading view of the same change `nitpick-tree-visit' opens the file for:
removed lines are text, unchanged context is folded away.  On a directory it
is everything under it, and nothing else unless `N' widens the diff.  What
following the point does on its own - this is how to ask for it with
`nitpick-tree-follow' off.

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
    (define-key map "O" #'nitpick-tree-visit-other)
    (define-key map "f" #'nitpick-tree-toggle-follow)
    ;; `N' rather than `n', which is `treemacs-next-line': the pane is walked
    ;; with it.  Under evil it costs the reverse search, which a pane of a
    ;; dozen file names has no use for.
    (define-key map "N" #'nitpick-tree-toggle-narrow)
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

     (defun nitpick-tree--render (root revision items stats &optional patch)
       "Render ITEMS in the current buffer as the pane for ROOT and REVISION.
STATS is what `nitpick-tree--totals' returned, for the header line.  PATCH is
the patch the pane was read from, or nil when git was."
       (treemacs-initialize nitpick-tree-root
         :with-expand-depth 'all
         :and-do (progn
                   (setq-local nitpick-tree--root root
                               nitpick-tree--revision revision
                               nitpick-tree--items items
                               nitpick-tree--patch patch
                               nitpick-tree--followed nil
                               treemacs-space-between-root-nodes nil
                               header-line-format
                               (nitpick-tree--header revision stats patch))
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
    (nitpick-tree--widen)
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
(defun nitpick-tree (root revision &optional patch)
  "Review what REVISION and ROOT's worktree differ by, file by file.

A side pane listing only those files, nested by directory, with each one's
status marker and line counts - and nothing else in the project, which is what
separates it from a file tree with git colours on it - and the diff of the
range beside it.  Moving in the pane narrows the diff to the file at point, or
to the subtree of the directory at point, so the review reads by walking the
pane; `N' gives the whole range back.

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

PATCH is for a pane with no worktree behind it - what `nitpick-pr' opens a
pull request with, and what `nitpick-tree-range' opens two revisions with -
and replaces REVISION as the source of both the file list and the diff.

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
  (if (and (null root) (null revision) (null patch))
      (nitpick-tree-close)
    (nitpick-tree--open root revision patch)))

;;;###autoload
(defun nitpick-tree-range (root range)
  "Review the two revisions RANGE names in ROOT, neither one checked out.

For reading work that is not yours: a colleague's branch against the base
they ask you to compare it with, while your own worktree stays where it is.
`A..B' compares the two endpoints and `A...B' compares B against the merge
base, the way git reads them.  A bare revision is the ordinary review of the
worktree against it, so that is what it opens.

The pane, the tree, the narrowing and the diff keys are the ones
`nitpick-tree' gives.  What a range cannot give is the worktree: `o' opens
each side as the read-only blob git holds, so there is no editing, no LSP and
no diff-hl painting of what is on screen.  `nitpick-comment' needs a pull
request, which a range is not - `nitpick-pr' is the command for one of those."
  (interactive
   (let ((root (or (magit-toplevel) (user-error "Not inside a git repository"))))
     (list root
           (let ((default-directory root))
             (magit-diff-read-range-or-commit "Tree of changes for range")))))
  (let ((sides (let ((default-directory root)) (magit-split-range range))))
    (if sides
        (nitpick-tree root nil (nitpick-tree--range-source root range sides))
      ;; Not a range: the worktree is one of the two sides after all.
      (nitpick-tree root range))))

(defun nitpick-tree--open (root revision &optional patch)
  "Render ROOT's differences from REVISION in the pane, and select it.
From PATCH instead, when there is one: its diff is washed first, because the
file list is read back out of it.
The diff beside it is read on a fresh opening, and re-read by a refresh that
finds it on screen.  Not by one that does not: a refresh runs on every commit
and every staging, and pushing a diff in front of the magit buffer the user is
committing from is not a redraw of the pane."
  (nitpick-tree--define)
  (nitpick-tree--paint)
  ;; Before reading the diff: this also caches the revision, which is what
  ;; stops a second opening from setting it again over an answer since given.
  (when (and (not patch)
             nitpick-tree-set-base
             (not (alist-get (nitpick-diff-hl--root root) nitpick-diff-hl--bases
                             nil nil #'string-equal)))
    (nitpick-diff-hl-set-base root revision))
  (let* ((fresh (not (nitpick-tree--window)))
         (diff (or fresh
                   (nitpick-tree--diff-on-screen-p)
                   ;; A pane whose diff was dropped has none to put back: the
                   ;; hand-off from a patch, where what is on screen is the
                   ;; patch's diff and the pane is now the checkout's.
                   (not (buffer-live-p nitpick-tree--diff-buffer))))
         (washed (and patch (nitpick-tree--patch-diff patch)))
         (files (if patch
                    (nitpick-tree--diff-changes washed)
                  (nitpick-tree--changes root revision)))
         (items (nitpick-tree--build files root))
         (stats (nitpick-tree--totals files))
         (existing (get-buffer nitpick-tree-buffer-name))
         ;; Where the pane was, so a refresh does not send point back to the
         ;; top of a review being read line by line.
         (line (and existing (with-current-buffer existing (line-number-at-pos))))
         (buffer (or existing (get-buffer-create nitpick-tree-buffer-name))))
    (nitpick-tree--take-frame)
    (with-current-buffer buffer
      (nitpick-tree--render root revision items stats patch))
    (let ((window (nitpick-tree--display buffer)))
      ;; The diff after the pane: the pane's side window is the one window
      ;; `nitpick-tree--main-window' has to pass over.
      (when diff
        (if patch
            (nitpick-tree--display-diff washed)
          (nitpick-tree--build-diff root revision)))
      (when window
        (select-window window)
        (when line
          (goto-char (point-min))
          (forward-line (1- line)))
        (nitpick-tree--goto-node)
        ;; Explicitly, rather than waiting for the hook: a refresh driven by
        ;; a magit hook ends with the point somewhere else entirely.  And only
        ;; where the diff was re-read, for the same reason it was not.
        (when diff
          (nitpick-tree--follow))))
    (when (called-interactively-p 'interactive)
      (message "%s" (nitpick-tree--header revision stats patch)))))

(defun nitpick-tree-refresh ()
  "Re-render the pane, if it is on screen, from what git says now.
A pane read from a patch re-washes the patch file: refreshing is not a reason
to ask the forge again.
On screen, not merely alive: re-rendering displays the pane, and a commit is
no reason to re-open one that was closed."
  (interactive)
  (let ((buffer (get-buffer nitpick-tree-buffer-name)))
    (when (and (buffer-live-p buffer) (get-buffer-window buffer t))
      (let ((root (buffer-local-value 'nitpick-tree--root buffer))
            (revision (buffer-local-value 'nitpick-tree--revision buffer))
            (patch (buffer-local-value 'nitpick-tree--patch buffer)))
        (when (or patch (and root revision))
          (save-selected-window
            (nitpick-tree root revision patch)))))))

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
