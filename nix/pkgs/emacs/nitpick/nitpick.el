;;; nitpick.el --- Batched pull request reviews from Emacs -*- lexical-binding: t; -*-

;; Author: dotless
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (magit "4.0"))
;; Keywords: vc, tools
;; URL: https://git.gutimore.net/gutimore/dotless

;;; Commentary:

;; Review a pull request from the files on disk: comment on the line at point,
;; batch the comments into a server-side pending review, submit them together
;; with a verdict.  Drafts live on the forge from the moment they are added, so
;; they survive a crash and stay submittable from the web UI.
;;
;; Commands: `nitpick-comment', `nitpick-list', `nitpick-submit',
;; `nitpick-refresh'.  `nitpick-mode' puts them on `nitpick-keymap-prefix' (C-c v by
;; default); leave it off to bind `nitpick-prefix-map' yourself.
;;
;; GitHub via the `gh' CLI is the only backend today; the public names are
;; backend-neutral so another forge can be added behind them.

;;; Code:

(require 'json)
(require 'seq)
(require 'project)

(declare-function magit-toplevel "magit-git" (&optional directory))
(declare-function magit-file-relative-name "magit-git" (&optional file tracked))
(declare-function magit-git-string "magit-git" (&rest args))
(declare-function magit-rev-verify "magit-git" (rev))
(declare-function magit-main-branch "magit-git" ())
(declare-function magit-rev-abbrev "magit-git" (rev))
(declare-function magit-rev-parse "magit-git" (&rest args))
(declare-function magit-git-lines "magit-git" (&rest args))
(declare-function magit-git-success "magit-git" (&rest args))
(declare-function magit-current-section "magit-section" ())
(declare-function magit-get-current-branch "magit-git" ())
(declare-function magit-list-local-branch-names "magit-git" ())
(declare-function magit-read-branch-or-commit "magit-git" (prompt &optional secondary-default exclude))
(declare-function magit-run-git "magit-process" (&rest args))
(declare-function magit-diff-range "magit-diff" (rev-or-range &optional args files))
(declare-function magit-diff-visit--sides "magit-diff" ())
(declare-function magit-diff-visit-file--setup "magit-diff" (buf pos))
(declare-function magit-diff-hunk-line "magit-diff" (section goto-from))
(declare-function magit-diff--hunk-section "magit-diff" ())
(declare-function magit-find-file-noselect "magit-files" (rev file &optional no-restore-position volatile))
(declare-function magit--file-index-stages "magit-git" (file))
(declare-function magit-git-insert "magit-git" (&rest args))
(declare-function magit-diff-arguments "magit-diff" (&optional mode))
(declare-function forge--get-remote "forge-repo" (&optional remote))
(declare-function diff-hl-set-reference-rev "diff-hl" (rev))
(declare-function diff-hl-set-reference-rev-in-project-internal "diff-hl" (rev project))
(declare-function diff-hl-highlight-on-fringe "diff-hl" (ovl type shape))
(declare-function diff-hl-highlight-on-fringe-flat "diff-hl" (ovl type shape))
(declare-function diff-hl-update "diff-hl" ())
(declare-function diff-hl-changes-buffer "diff-hl" (file backend &optional new-rev bufname))
(declare-function diff-hl-flydiff-changes-buffer "diff-hl-flydiff" (file backend &optional new-rev buffer))
(declare-function project-buffers "project" (project))
(defvar diff-hl-mode)
(defvar diff-hl-reference-revision)
(defvar magit-buffer-diff-range)
(defvar magit-buffer-diff-type)
(defvar magit-buffer-revision)
(defvar diff-hl-update-async)
(defvar vc-git-diff-switches)
(defvar diff-hl-highlight-function)
(defvar diff-hl-highlight-reference-function)
(defvar diff-hl-fringe-flat-bmp)
(defvar diff-hl-spec-cache)
(defvar diff-hl-fringe-face-function)
(declare-function projectile-invalidate-cache "projectile" (prompt))
(declare-function eieio-oref "eieio-core" (obj slot))

(defgroup nitpick nil
  "Batched pull request reviews from the files on disk."
  :group 'tools
  :prefix "nitpick-")

(defcustom nitpick-gh-executable "gh"
  "The `gh' CLI used to talk to GitHub.  Nix pins this to a store path."
  :type 'string
  :group 'nitpick)

(defun nitpick--gh ()
  "Return the usable `gh' executable, or signal a user error."
  (or (if (file-name-absolute-p nitpick-gh-executable)
          (and (file-executable-p nitpick-gh-executable) nitpick-gh-executable)
        (executable-find nitpick-gh-executable))
      (user-error "The `gh' CLI is not available (see `nitpick-gh-executable')")))

(defun nitpick--remote ()
  "Return the git remote to resolve branches against."
  (or (and (fboundp 'forge--get-remote) (forge--get-remote)) "origin"))

(defvar-local nitpick--comment-ctx nil
  "Context alist for the inline PR comment being composed.")
(defvar-local nitpick--submit-ctx nil
  "Context alist (root, review, event, number) for a review being submitted.")

;;;; Backend: GitHub GraphQL over the `gh' CLI

(defun nitpick--graphql (query variables)
  "Run GraphQL QUERY with VARIABLES (an alist) via `gh'; return the `data' alist.
Arrays parse to lists, objects to alists.  Signals an error on transport failure
or a GraphQL `errors' array (gh returns those with a non-zero exit)."
  (let ((gh (nitpick--gh))
        (payload (json-encode `((query . ,query)
                                (variables . ,(or variables (make-hash-table))))))
        (out (generate-new-buffer " *nitpick-graphql*")))
    (unwind-protect
        (let ((exit (with-temp-buffer
                      (insert payload)
                      (call-process-region (point-min) (point-max) gh nil out nil
                                           "api" "graphql" "--input" "-"))))
          (with-current-buffer out
            (goto-char (point-min))
            (let* ((resp (ignore-errors
                           (json-parse-buffer :object-type 'alist :array-type 'list)))
                   (errs (alist-get 'errors resp)))
              (when (or (not (integerp exit)) (/= exit 0) errs)
                (error "GraphQL: %s"
                       (or (and errs (alist-get 'message (car errs)))
                           (buffer-string))))
              (alist-get 'data resp))))
      (kill-buffer out))))

(defun nitpick--pr-ctx (&optional root)
  "Return an alist of PR context for ROOT (default `magit-toplevel').
Keys: `id' (node id), `number', `base' (base branch), `head' (head SHA).
Errors if the current branch has no associated open PR."
  (let* ((default-directory (or root (magit-toplevel)
                                (user-error "Not inside a git repository")))
         (out (generate-new-buffer " *nitpick-pr-view*")))
    (unwind-protect
        (if (/= 0 (call-process (nitpick--gh) nil out nil "pr" "view"
                                "--json" "id,number,baseRefName,headRefOid"))
            (error "gh pr view failed (does this branch have an open PR?):\n%s"
                   (with-current-buffer out (buffer-string)))
          (with-current-buffer out
            (goto-char (point-min))
            (let ((j (json-parse-buffer :object-type 'alist)))
              (list (cons 'id (alist-get 'id j))
                    (cons 'number (alist-get 'number j))
                    (cons 'base (alist-get 'baseRefName j))
                    (cons 'head (alist-get 'headRefOid j))))))
      (kill-buffer out))))

(defun nitpick--pending-review (pr-id)
  "Return the viewer's pending review node id for PR-ID, or nil.
Pending reviews are private to their author, so states:[PENDING] returns only
our own."
  (let* ((q "query($pr:ID!){ node(id:$pr){ ... on PullRequest {
               reviews(first:20, states:[PENDING]){ nodes { id } } } } }")
         (data (nitpick--graphql q `((pr . ,pr-id))))
         (nodes (alist-get 'nodes (alist-get 'reviews (alist-get 'node data)))))
    (alist-get 'id (car nodes))))

(defun nitpick--ensure-review (pr-id head)
  "Return the viewer's pending review id for PR-ID, creating one pinned to HEAD."
  (or (nitpick--pending-review pr-id)
      (let* ((q "mutation($pr:ID!,$oid:GitObjectID!){
                   addPullRequestReview(input:{pullRequestId:$pr, commitOID:$oid}){
                     pullRequestReview { id } } }")
             (data (nitpick--graphql q `((pr . ,pr-id) (oid . ,head)))))
        (alist-get 'id (alist-get 'pullRequestReview
                                  (alist-get 'addPullRequestReview data))))))

(defun nitpick--add-thread (review-id path line start-line body &optional side)
  "Add a draft thread to REVIEW-ID at PATH, on SIDE (\"RIGHT\" unless given).
It covers LINE, or the range START-LINE..LINE when START-LINE differs.  SIDE
is \"RIGHT\" for the PR's own lines and \"LEFT\" for the base's."
  (let* ((side (or side "RIGHT"))
         (range (and start-line (/= start-line line)))
         (q (if range
                "mutation($r:ID!,$p:String!,$b:String!,$l:Int!,$s:Int!,$d:DiffSide!){
                   addPullRequestReviewThread(input:{pullRequestReviewId:$r,path:$p,
                     body:$b,line:$l,side:$d,startLine:$s,startSide:$d}){
                     thread { id } } }"
              "mutation($r:ID!,$p:String!,$b:String!,$l:Int!,$d:DiffSide!){
                   addPullRequestReviewThread(input:{pullRequestReviewId:$r,path:$p,
                     body:$b,line:$l,side:$d}){ thread { id } } }"))
         (vars (append `((r . ,review-id) (p . ,path) (b . ,body) (l . ,line)
                         (d . ,side))
                       (when range `((s . ,start-line))))))
    (nitpick--graphql q vars)))

;;;; Targets: a file's own lines, or the hunk at point in a diff buffer

(defun nitpick--oref (object slot)
  "Return SLOT of OBJECT.
Through `eieio-oref' with the slot in a variable: a literal makes the
byte-compiler check it against magit classes it cannot see at build time."
  (eieio-oref object slot))

(defun nitpick--diff-buffer-p ()
  "Non-nil in a magit diff buffer whose new side is the PR's own.
Not a revision buffer: a commit's new-side line numbers are the PR head's
only for the last commit on the branch.  Magit's status buffer is not a diff
buffer at all, and its hunks are the worktree's changes."
  (and (derived-mode-p 'magit-diff-mode)
       (not (derived-mode-p 'magit-revision-mode))))

(defun nitpick--diff-hunk-at-point ()
  "Return the magit hunk section at point, or nil when point is not on one."
  (and (nitpick--diff-buffer-p)
       (fboundp 'magit-current-section)
       (let ((section (magit-current-section)))
         (and section
              (eq (nitpick--oref section 'type) 'hunk)
              section))))

(defun nitpick--hunk-path (section)
  "Return the path of the file SECTION belongs to.
Its file section's value, which for a rename is the new name - the one the
forge knows the file by."
  (let* ((parent (nitpick--oref section 'parent))
         (path (and parent (nitpick--oref parent 'value))))
    (if (stringp path) path
      (user-error "Cannot tell which file the hunk at point belongs to"))))

(defun nitpick--hunk-body (section)
  "Return SECTION's body as one (POS CHAR NEW OLD) tuple per diff line.
POS starts the line and CHAR is its diff marker; NEW and OLD are the line
numbers it has on the PR's side and on the base's, nil on the side where it
does not exist."
  (let ((new (car (nitpick--oref section 'to-range)))
        (old (car (nitpick--oref section 'from-range)))
        (end (nitpick--oref section 'end))
        (body nil))
    (save-excursion
      (goto-char (nitpick--oref section 'content))
      (while (< (point) end)
        (pcase (char-after (point))
          (?+ (push (list (point) ?+ new nil) body)
              (setq new (1+ new)))
          (?- (push (list (point) ?- nil old) body)
              (setq old (1+ old)))
          ;; "\ No newline at end of file" is part of the hunk and is not a
          ;; line of either file.
          (?\\ nil)
          (_ (push (list (point) ?\s new old) body)
             (setq new (1+ new))
             (setq old (1+ old))))
        (forward-line)))
    (nreverse body)))

(defun nitpick--hunk-selection (section beg end)
  "Return (SIDE START-LINE END-LINE) for the lines of SECTION in BEG..END.
The whole hunk when BEG is nil.  The added lines set the range when the
selection has any, the removed lines when it has only those, and the context
lines when it has neither: a removal is commented on the base side, anything
else on the PR's."
  (let* ((body (nitpick--hunk-body section))
         (sel (if beg
                  (seq-filter (lambda (l) (and (>= (car l) beg) (<= (car l) end)))
                              body)
                body))
         (added (seq-filter (lambda (l) (eq (nth 1 l) ?+)) sel))
         (removed (seq-filter (lambda (l) (eq (nth 1 l) ?-)) sel)))
    (cond (added (list "RIGHT" (nth 2 (car added)) (nth 2 (car (last added)))))
          (removed (list "LEFT" (nth 3 (car removed)) (nth 3 (car (last removed)))))
          (sel (list "RIGHT" (nth 2 (car sel)) (nth 2 (car (last sel))))))))

(defun nitpick--whole-lines (beg end)
  "Return BEG..END grown to whole lines as a (BEG . END) cons, nil for a nil BEG.
An END at the beginning of a line ends the line before it: a line-wise
selection leaves point past the last line it covers."
  (and beg
       (save-excursion
         (cons (progn (goto-char beg) (line-beginning-position))
               (progn (goto-char end)
                      (when (and (> end beg) (bolp)) (backward-char))
                      (line-end-position))))))

(defun nitpick--hunk-target (section beg end)
  "Return the comment target for the part of SECTION that BEG..END covers.
The whole hunk when BEG is nil.  See `nitpick--comment-target' for the keys."
  (when (nitpick--oref section 'combined)
    (user-error "A combined diff has no single side to comment on"))
  (let* ((root (or (magit-toplevel) (user-error "Not inside a git repository")))
         (path (nitpick--hunk-path section))
         (bounds (nitpick--whole-lines beg end))
         (sel (or (nitpick--hunk-selection section (car bounds) (cdr bounds))
                  (user-error "No line of the PR in the hunk at point")))
         (default-directory root))
    ;; The new side of this diff is the worktree, so its line numbers are the
    ;; PR head's only while the file is the committed one.
    (unless (magit-git-success "diff" "--quiet" "HEAD" "--" path)
      (user-error "%s has uncommitted changes: its lines are not the PR's" path))
    (list (cons 'root root) (cons 'path path)
          (cons 'line (nth 2 sel))
          (cons 'start-line (and (/= (nth 1 sel) (nth 2 sel)) (nth 1 sel)))
          (cons 'side (car sel)))))

(defun nitpick--file-target (beg end)
  "Return the comment target for BEG..END in the visited file.
Nil bounds mean the line at point."
  (unless buffer-file-name (user-error "Buffer is not visiting a file"))
  (when (buffer-modified-p)
    (user-error "Save the buffer first: line numbers must match the PR head"))
  (let* ((beg (or beg (line-beginning-position)))
         (end (or end (line-end-position)))
         (root (or (magit-toplevel) (user-error "Not inside a git repository")))
         (path (or (magit-file-relative-name buffer-file-name)
                   (user-error "File is not inside the repository")))
         (start-line (line-number-at-pos beg))
         (end-line (save-excursion
                     (goto-char end)
                     (when (and (> end beg) (bolp)) (backward-char))
                     (line-number-at-pos))))
    (list (cons 'root root) (cons 'path path)
          (cons 'line end-line)
          (cons 'start-line (and (/= start-line end-line) start-line))
          (cons 'side "RIGHT"))))

(defun nitpick--comment-target (beg end)
  "Return what BEG..END points at, as an alist to compose a comment against.
Keys: `root', `path', `line', `start-line' (nil unless the target is a range)
and `side'.  The hunk at point in a diff buffer, the visited file's own lines
anywhere else."
  (let ((section (nitpick--diff-hunk-at-point)))
    (cond (section (nitpick--hunk-target section beg end))
          ((nitpick--diff-buffer-p) (user-error "Point is not on a diff hunk"))
          (t (nitpick--file-target beg end)))))

;;;; Commands

;;;###autoload
(defun nitpick-comment (&optional beg end)
  "Add an inline review comment as a draft on this PR's pending review.
It is saved to the pending review immediately (created if needed), so it is
server-side and crash-safe.  Publish the whole review later via
`nitpick-submit' or Forge's approve / request-changes.

What it comments on depends on where it is called:

In a file buffer, the line at point, or the line range BEG..END when a region
is active.

In a magit diff buffer - `nitpick-diff-buffer-file', the changed-file pane's
`d', any `magit-diff' - the hunk at point, or the part of it a region covers.
A selection of removed lines is commented on the base side, anything else on
the PR's.  Magit's own status buffer is not a diff buffer: its hunks are the
worktree's, not the PR's.

The line(s) must be part of the PR's diff (a changed line, or context inside
a hunk); the forge rejects anything outside it."
  (interactive (if (use-region-p) (list (region-beginning) (region-end)) nil))
  (nitpick--gh)
  (let* ((ctx (nitpick--comment-target beg end))
         (path (alist-get 'path ctx))
         (line (alist-get 'line ctx))
         (start (alist-get 'start-line ctx))
         (buf (get-buffer-create "*nitpick-comment*")))
    (with-current-buffer buf
      (erase-buffer)
      (when (fboundp 'gfm-mode) (gfm-mode))
      (setq nitpick--comment-ctx ctx)
      (setq header-line-format
            (format " Draft PR comment on %s:%s%s  -  C-c C-c add - C-c C-k cancel"
                    path
                    (if start (format "%d-%d" start line) line)
                    (if (equal (alist-get 'side ctx) "LEFT") " (base side)" "")))
      (local-set-key (kbd "C-c C-c") #'nitpick--comment-add)
      (local-set-key (kbd "C-c C-k") #'nitpick-cancel))
    (pop-to-buffer buf)
    (message "Write your comment, then C-c C-c to add it to the pending review")))

;;;###autoload
(defun nitpick-cancel ()
  "Abort the comment / review composer."
  (interactive)
  (let ((b (current-buffer))) (quit-window) (kill-buffer b)))

(defun nitpick--comment-add ()
  "Add the composed comment as a draft thread on the PR's pending review."
  (interactive)
  (let* ((ctx nitpick--comment-ctx)
         (body (string-trim (buffer-substring-no-properties (point-min) (point-max))))
         (default-directory (alist-get 'root ctx)))
    (when (string-empty-p body) (user-error "Comment body is empty"))
    (let* ((pr (nitpick--pr-ctx default-directory))
           (local (string-trim (shell-command-to-string "git rev-parse HEAD"))))
      (when (and (stringp (alist-get 'head pr))
                 (not (string-prefix-p local (alist-get 'head pr)))
                 (not (string-prefix-p (alist-get 'head pr) local)))
        (message "Warning: worktree HEAD differs from PR head - run `nitpick-refresh'"))
      (nitpick--add-thread
       (nitpick--ensure-review (alist-get 'id pr) (alist-get 'head pr))
       (alist-get 'path ctx) (alist-get 'line ctx) (alist-get 'start-line ctx) body
       (alist-get 'side ctx))
      (let ((b (current-buffer))) (quit-window) (kill-buffer b))
      (message "Added draft comment to pending review of PR #%s" (alist-get 'number pr)))))

;;;###autoload
(defun nitpick-list ()
  "List the draft comments in this PR's pending review, read live from the forge."
  (interactive)
  (let* ((root (or (magit-toplevel) (user-error "Not inside a git repository")))
         (default-directory root)
         (pr (nitpick--pr-ctx root))
         (rid (nitpick--pending-review (alist-get 'id pr))))
    (unless rid (user-error "No pending review for PR #%s" (alist-get 'number pr)))
    (let* ((q "query($r:ID!){ node(id:$r){ ... on PullRequestReview {
                 comments(first:100){ nodes { path line startLine outdated body } } } } }")
           (items (alist-get 'nodes (alist-get 'comments
                    (alist-get 'node (nitpick--graphql q `((r . ,rid)))))))
           (buf (get-buffer-create "*nitpick*")))
      (with-current-buffer buf
        (setq buffer-read-only nil)
        (erase-buffer)
        (insert (format "Pending review - PR #%s - %d draft comment(s)   (q: quit)\n\n"
                        (alist-get 'number pr) (length items)))
        (dolist (it items)
          (insert (propertize
                   (format "%s:%s%s\n" (alist-get 'path it)
                           (if (alist-get 'startLine it)
                               (format "%s-%s" (alist-get 'startLine it) (alist-get 'line it))
                             (or (alist-get 'line it) "?"))
                           (if (eq t (alist-get 'outdated it)) "   [OUTDATED]" ""))
                   'face 'bold))
          (insert (or (alist-get 'body it) "") "\n\n"))
        (goto-char (point-min))
        (setq buffer-read-only t)
        (local-set-key (kbd "q") #'quit-window))
      (pop-to-buffer buf))))

;;;###autoload
(defun nitpick-submit (&optional event)
  "Submit this PR's pending review.
EVENT is `comment' (default), `approve', or `request-changes'.  Opens a composer
for the summary body; C-c C-c publishes all draft comments together with the
verdict."
  (interactive)
  (let* ((event (or event 'comment))
         (root (or (magit-toplevel) (user-error "Not inside a git repository")))
         (default-directory root)
         (pr (nitpick--pr-ctx root))
         (rid (nitpick--pending-review (alist-get 'id pr)))
         (gh-event (pcase event
                     ('approve "APPROVE") ('request-changes "REQUEST_CHANGES") (_ "COMMENT"))))
    (unless rid (user-error "No pending review to submit for PR #%s" (alist-get 'number pr)))
    (let ((buf (get-buffer-create "*nitpick-submit*")))
      (with-current-buffer buf
        (erase-buffer)
        (when (fboundp 'gfm-mode) (gfm-mode))
        (setq nitpick--submit-ctx
              (list (cons 'root root) (cons 'review rid)
                    (cons 'event gh-event) (cons 'number (alist-get 'number pr))))
        (setq header-line-format
              (format " Submit %s review of PR #%s  -  C-c C-c publish - C-c C-k cancel"
                      gh-event (alist-get 'number pr)))
        (local-set-key (kbd "C-c C-c") #'nitpick--submit-send)
        (local-set-key (kbd "C-c C-k") #'nitpick-cancel))
      (pop-to-buffer buf)
      (message "Optional summary, then C-c C-c to publish the %s review" gh-event))))

(defun nitpick--submit-send ()
  "Publish the pending review with the chosen event and summary body."
  (interactive)
  (let* ((ctx nitpick--submit-ctx)
         (body (string-trim (buffer-substring-no-properties (point-min) (point-max))))
         (default-directory (alist-get 'root ctx))
         (q "mutation($r:ID!,$e:PullRequestReviewEvent!,$b:String){
               submitPullRequestReview(input:{pullRequestReviewId:$r,event:$e,body:$b}){
                 pullRequestReview { url state } } }")
         (vars (append `((r . ,(alist-get 'review ctx)) (e . ,(alist-get 'event ctx)))
                       (unless (string-empty-p body) `((b . ,body)))))
         (data (nitpick--graphql q vars))
         (url (alist-get 'url (alist-get 'pullRequestReview
                                         (alist-get 'submitPullRequestReview data))))
         (b (current-buffer)))
    (quit-window)
    (kill-buffer b)
    (message "Submitted %s review of PR #%s%s"
             (alist-get 'event ctx) (alist-get 'number ctx)
             (if url (concat ": " url) ""))))

;;;###autoload
(defun nitpick-refresh ()
  "Resync the worktree and diff-hl to the PR's latest head, report stale drafts.
Run after the author pushes new commits mid-review.  Aborts if the worktree has
uncommitted changes (a review worktree should have none)."
  (interactive)
  (let* ((root (or (magit-toplevel) (user-error "Not inside a git repository")))
         (default-directory root))
    (unless (string-empty-p (string-trim (shell-command-to-string "git status --porcelain")))
      (user-error "Worktree has local changes; commit or stash before refreshing"))
    (let* ((pr (nitpick--pr-ctx root))
           (new-head (alist-get 'head pr)))
      (magit-run-git "fetch")
      (magit-run-git "reset" "--hard" new-head)
      (when (fboundp 'projectile-invalidate-cache) (projectile-invalidate-cache nil))
      (nitpick-diff-hl-set-base root (alist-get 'base pr))
      (let ((rid (nitpick--pending-review (alist-get 'id pr))))
        (if (not rid)
            (message "Resynced PR #%s to %s (no pending review)"
                     (alist-get 'number pr) (substring new-head 0 7))
          (let* ((q "query($r:ID!){ node(id:$r){ ... on PullRequestReview {
                       comments(first:100){ nodes { outdated } } } } }")
                 (items (alist-get 'nodes (alist-get 'comments
                          (alist-get 'node (nitpick--graphql q `((r . ,rid)))))))
                 (n-out (seq-count (lambda (c) (eq t (alist-get 'outdated c))) items)))
            (message "Resynced PR #%s to %s - %d/%d draft comment(s) now outdated%s"
                     (alist-get 'number pr) (substring new-head 0 7)
                     n-out (length items)
                     (if (> n-out 0) " (`nitpick-list' to review)" ""))))))))

;;;; diff-hl: paint the changed lines, not only the fringe

(defface nitpick-diff-hl-line-insert
  '((((background dark))  :extend t :background "#1e2d1e")
    (((background light)) :extend t :background "#e3f7e3"))
  "Background for whole lines the PR adds."
  :group 'nitpick)

(defface nitpick-diff-hl-line-change
  '((((background dark))  :extend t :background "#20293d")
    (((background light)) :extend t :background "#e0e8ff"))
  "Background for whole lines the PR modifies."
  :group 'nitpick)

(defface nitpick-diff-hl-delete
  '((((background dark))  :foreground "#bf616a")
    (((background light)) :foreground "#a33a3a"))
  "Fringe colour for a line the base has and this revision does not.
`diff-hl-delete' is what diff-hl would use, and it carries no colour of its
own: themes that leave it alone paint the marker in the fringe's own
foreground, which reads as neither added nor removed."
  :group 'nitpick)

(defcustom nitpick-diff-hl-line-faces
  '((insert . nitpick-diff-hl-line-insert)
    (change . nitpick-diff-hl-line-change))
  "Face per diff-hl change type.  A type absent here keeps the fringe only.
`delete' is absent on purpose: the overlay sits on the line after the removed
text, so painting it would mark a line the PR never touched."
  :type '(alist :key-type symbol :value-type face)
  :group 'nitpick)

(defun nitpick-diff-hl--forget-specs ()
  "Empty diff-hl's cache of fringe specs.
`diff-hl-fringe-spec' keys on the change type and the two functions that
pick a face and a bitmap, not on the bitmap itself, so a spec built before
`nitpick-diff-hl-delete-bmp' applied is handed back for ever otherwise."
  (when (boundp 'diff-hl-spec-cache)
    (clrhash diff-hl-spec-cache)))

(defcustom nitpick-diff-hl-delete-bmp 'diff-hl-bmp-delete
  "Fringe bitmap marking a removal against the base.
diff-hl draws changes against a reference with `diff-hl-fringe-flat-bmp',
which is empty by default because the whole-line background is the marker.
A removal gets no background - it would colour the line after the deleted
text, which the branch never touched - so with the empty bitmap it has
nothing at all.  Set to `diff-hl-bmp-empty' to go back to that."
  :type 'symbol
  :group 'nitpick
  :set (lambda (symbol value)
         (set-default symbol value)
         (nitpick-diff-hl--forget-specs)))

(defcustom nitpick-diff-hl-line-priority -60
  "Overlay priority of the line backgrounds.
Below `hl-line''s -50, so the cursor line keeps its own colour."
  :type 'integer
  :group 'nitpick)

(defvar nitpick-diff-hl--bases nil
  "Alist of (ROOT . REVISION) last given to `nitpick-diff-hl-set-base'.
The preselected answer next time, so a worktree does not ask the forge twice.
It never decides what is drawn; diff-hl's own reference is the only state.")

(defvar nitpick-diff-hl--saved nil
  "The two diff-hl highlight functions `nitpick-diff-hl-line-mode' replaced.
A cons of the working-tree one and the reference one.  Kept so the mode
delegates to them instead of assuming fringes, and puts them back on exit.")

(defun nitpick-diff-hl--inner (reference)
  "Return the highlight function wrapped for the REFERENCE or working pass."
  (or (if reference (cdr nitpick-diff-hl--saved) (car nitpick-diff-hl--saved))
      (if reference #'diff-hl-highlight-on-fringe-flat #'diff-hl-highlight-on-fringe)))

(defun nitpick-diff-hl--paint-line (ovl type)
  "Stretch OVL over its whole line and paint it for diff-hl's TYPE.
Point is at the start of the line diff-hl is highlighting.  The trailing
newline is included so the `:extend' faces reach the window edge."
  (if-let* ((face (alist-get type nitpick-diff-hl-line-faces)))
      (progn
        (move-overlay ovl (line-beginning-position)
                      (min (point-max) (1+ (line-end-position))))
        (overlay-put ovl 'face face)
        (overlay-put ovl 'priority nitpick-diff-hl-line-priority))
    ;; diff-hl recycles overlays between its two passes; clear a stale face.
    (overlay-put ovl 'face nil)))

(defun nitpick-diff-hl-highlight-line (ovl type shape)
  "Highlight OVL as diff-hl would, then paint its whole line.
For the working-tree pass; TYPE and SHAPE are diff-hl's."
  (funcall (nitpick-diff-hl--inner nil) ovl type shape)
  (nitpick-diff-hl--paint-line ovl type))

(defun nitpick-diff-hl--delete-face (&rest _)
  "Return the face for a removal's fringe marker.
A function, and a named one, because that is what `diff-hl-fringe-spec'
asks for and what it keys its cache on."
  'nitpick-diff-hl-delete)

(defun nitpick-diff-hl-highlight-line-flat (ovl type shape)
  "Highlight OVL as diff-hl would, then paint its whole line.
For the reference-revision pass; TYPE and SHAPE are diff-hl's.
A removal is drawn with `nitpick-diff-hl-delete-bmp' in
`nitpick-diff-hl-delete': the one change with no line background to be seen
by, so it is also the one that needs the fringe to carry the colour."
  (if (eq type 'delete)
      (let ((diff-hl-fringe-flat-bmp nitpick-diff-hl-delete-bmp)
            (diff-hl-fringe-face-function #'nitpick-diff-hl--delete-face))
        (funcall (nitpick-diff-hl--inner t) ovl type shape))
    (funcall (nitpick-diff-hl--inner t) ovl type shape))
  (nitpick-diff-hl--paint-line ovl type))

(defun nitpick-diff-hl--redraw ()
  "Rebuild the diff-hl overlays of every buffer that has them."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (bound-and-true-p diff-hl-mode) (diff-hl-update)))))

;;;###autoload
(define-minor-mode nitpick-diff-hl-line-mode
  "Show diff-hl changes as whole-line backgrounds, not just fringe marks.

Both of diff-hl's highlight slots are swapped: `diff-hl-highlight-function'
for working-tree changes and `diff-hl-highlight-reference-function' for
changes against the reference revision.  Reviewing a PR goes through the
second one, so setting only the first would leave the PR's own lines bare.

Whatever those slots held still runs, so the fringe or margin marks stay."
  :global t
  :group 'nitpick
  (if nitpick-diff-hl-line-mode
      (progn
        (unless nitpick-diff-hl--saved
          (setq nitpick-diff-hl--saved (cons diff-hl-highlight-function
                                          diff-hl-highlight-reference-function)))
        (setq diff-hl-highlight-function #'nitpick-diff-hl-highlight-line
              diff-hl-highlight-reference-function #'nitpick-diff-hl-highlight-line-flat))
    (when nitpick-diff-hl--saved
      (setq diff-hl-highlight-function (car nitpick-diff-hl--saved)
            diff-hl-highlight-reference-function (cdr nitpick-diff-hl--saved)
            nitpick-diff-hl--saved nil)))
  (nitpick-diff-hl--forget-specs)
  (nitpick-diff-hl--redraw))

;;;; diff-hl: give it the zero-context diffs it parses

(defconst nitpick--git-diff-algorithm-switches
  '("--histogram" "--patience" "--minimal" "--textconv")
  "Git diff switches worth keeping when zero context is forced on.
The set diff-hl itself keeps: they pick the algorithm, not the format.")

(defun nitpick--zero-context (orig &rest args)
  "Call ORIG with git's diff switches forced to zero context.
diff-hl reads a hunk header as if every diff were `-U0', taking the header's
start line as the first line that changed.  It does ask for `-U0' itself, but
on a compiled build that binding does not reach git - the call goes out with
the global switches - and then a hunk with context anchors its changes at the
context line it starts on.  Three lines of context, three lines too high."
  (let ((vc-git-diff-switches
         (cons "-U0" (seq-filter
                      (lambda (switch)
                        (member switch nitpick--git-diff-algorithm-switches))
                      ;; unbound until vc-git loads, and t means "use the
                      ;; global default", neither of which is a list
                      (and (boundp 'vc-git-diff-switches)
                           (listp vc-git-diff-switches)
                           vc-git-diff-switches)))))
    (apply orig args)))

(defconst nitpick--diff-hl-diff-functions
  '((diff-hl . diff-hl-changes-buffer)
    (diff-hl-flydiff . diff-hl-flydiff-changes-buffer))
  "diff-hl functions that run git, each with the feature that defines it.
Both need wrapping: `diff-hl-flydiff-mode' puts an `:override' on the first
that calls the second, and an `:override' never reaches what it covers, so
wrapping only the first does nothing for as long as flydiff is on.")

;; The deferred wrapping reads the mode the mode body turns on, and a warning
;; fails the build, so declare it before the function reads it.
(defvar nitpick-diff-hl-zero-context-mode)

(defun nitpick--diff-hl-advise ()
  "Wrap each of `nitpick--diff-hl-diff-functions', as its feature loads."
  (dolist (entry nitpick--diff-hl-diff-functions)
    (let ((feature (car entry))
          (fn (cdr entry)))
      (if (featurep feature)
          (advice-add fn :around #'nitpick--zero-context)
        (eval-after-load feature
          (lambda ()
            (when nitpick-diff-hl-zero-context-mode
              (advice-add fn :around #'nitpick--zero-context))))))))

(defun nitpick--diff-hl-unadvise ()
  "Take `nitpick--zero-context' off every function it was put on."
  (dolist (entry nitpick--diff-hl-diff-functions)
    (advice-remove (cdr entry) #'nitpick--zero-context)))

;;;###autoload
(define-minor-mode nitpick-diff-hl-zero-context-mode
  "Correct the lines diff-hl marks, by forcing `-U0' on the diffs it parses.
Off, the fringe and the painted lines can sit above the change they belong
to.  A workaround for the build, not for diff-hl's design; it goes when the
binding reaches git on its own."
  :global t
  :group 'nitpick
  ;; Each function is wrapped as its own feature loads: this mode is turned
  ;; on from a config file, where diff-hl is usually still waiting to be
  ;; autoloaded, and advice put on it before that is listed afterwards but
  ;; never runs again.
  (if nitpick-diff-hl-zero-context-mode
      (nitpick--diff-hl-advise)
    (nitpick--diff-hl-unadvise)))

;;;; diff-hl: annotate the worktree with the PR's own changes

;;;###autoload
(defconst nitpick--merge-base-suffix "..."
  "What a revision ends with to ask for the merge-base, as git spells it.")

(defun nitpick--base-revision (revision)
  "Return what diff-hl should compare against for REVISION.
REVISION as typed, so the default matches `git diff REVISION'.  A trailing
`...' resolves to the merge-base with HEAD instead, the explicit case in git
too.  Nil when it ends there and the merge-base cannot be worked out."
  (if (string-suffix-p nitpick--merge-base-suffix revision)
      (let ((rev (substring revision 0 (- (length nitpick--merge-base-suffix)))))
        (magit-git-string "merge-base" rev "HEAD"))
    revision))

(defun nitpick-diff-hl-set-base (root revision)
  "Diff the ROOT project against REVISION instead of its checked-out state.

REVISION is used as picked - a local branch, a remote-tracking ref like
`origin/master', a tag, a sha.  Nothing is prefixed for you, so `master' and
`origin/master' are different answers.  Pick HEAD for the usual view of your
own uncommitted edits.

REVISION is compared as `git diff REVISION' does, against its tip, so what
you see here is what magit's diff of the same revision shows.  A trailing
`...' asks for the merge-base instead, the way git's own three-dot range
does: `master' is every line that differs from master now, `master...' is
only what this branch changed since it left master.

diff-hl is pointed at the revision itself, not at a resolved sha, so a
branch that moves is followed.  Set project-locally, so newly opened files
inherit it and other projects are untouched.

The revision only.  Whole lines instead of fringe marks is
`nitpick-diff-hl-line-mode', switched on its own."
  (interactive
   (let ((root (or (magit-toplevel) (user-error "Not inside a git repository"))))
     (list root (let ((default-directory root))
                  (magit-read-branch-or-commit
                   "Diff against" (nitpick-diff-hl--suggested-base root))))))
  (condition-case err
      (let* ((default-directory root)
             (base (nitpick--base-revision revision))
             (rev (and base (magit-rev-verify base)))
             (proj (project-current nil root))
             (remember
              (lambda ()
                (setf (alist-get (nitpick-diff-hl--root root) nitpick-diff-hl--bases
                                 nil nil #'string-equal)
                      revision))))
        (cond
         ((not rev)
          (message "diff-hl: could not resolve %s" revision))
         ((and proj (fboundp 'diff-hl-set-reference-rev-in-project-internal))
          (funcall remember)
          (diff-hl-set-reference-rev-in-project-internal base proj)
          (nitpick-diff-hl--repaint proj)
          (message "diff-hl: %s now shows changes vs %s (%s)"
                   (file-name-nondirectory (directory-file-name root))
                   revision (magit-rev-abbrev rev)))
         ((fboundp 'diff-hl-set-reference-rev)
          ;; Older diff-hl without per-project references: fall back to global.
          (funcall remember)
          (diff-hl-set-reference-rev base)
          (nitpick-diff-hl--repaint nil)
          (message "diff-hl: showing changes vs %s (%s) [global]"
                   revision (magit-rev-abbrev rev)))))
    (error
     (message "diff-hl base not set: %s" (error-message-string err)))))

(defun nitpick-diff-show (revision files &optional stay)
  "Show FILES\=' changes against REVISION in a magit diff buffer.
REVISION is passed as given, so resolve a `...\=' with
`nitpick--base-revision\=' first.  FILES is a pathspec relative to the
repository root.  Unless STAY is non-nil the diff buffer is selected, the way
magit\='s own commands leave it.

`car\=' of the arguments: `magit-diff-arguments\=' answers (ARGS FILES),
filling both of the interactive slots it is written for, and its FILES is
whatever the last magit diff was limited to - which git would then read as a
revision.  Taking only ARGS keeps the user\='s diff settings without their
last diff\='s paths."
  (let ((show (lambda ()
                (magit-diff-range revision (car (magit-diff-arguments)) files))))
    (if stay (save-selected-window (funcall show)) (funcall show))))

;;;###autoload
(defun nitpick-diff-buffer-file (&optional stay)
  "Show this file\='s changes against the revision under review.

The same magit diff the changed-file pane opens with `d\=', for the file
being visited rather than the one at point in the pane - so a file reached
any other way still reads as a diff, with removed lines as text and
unchanged context folded away.

The revision is the one this worktree picked, and failing that whatever
`nitpick-diff-hl-set-base\=' would suggest.  Not `magit-diff-buffer-file\=',
which compares against the current branch or HEAD and so shows nothing of
what the branch itself changed.

With a prefix argument STAY the diff is shown but the current window keeps
the focus."
  (interactive "P")
  (let* ((root (or (magit-toplevel) (user-error "Not inside a git repository")))
         (file (or (magit-file-relative-name)
                   (user-error "Buffer is not visiting a file in %s" root)))
         (default-directory root)
         (picked (or (nitpick-diff-hl--suggested-base root)
                     (user-error "No revision to diff against")))
         (revision (or (nitpick--base-revision picked)
                       (user-error "Cannot work out a merge base for %s" picked))))
    (nitpick-diff-show revision (list file) stay)))

;;;; Visiting: the version a line belongs to, and the other one
;;
;; One rule: the point names a file and a line on two or more sides, and the
;; keystroke names which side to open.  `nitpick-visit' opens the side the line
;; at point belongs to - an added line is in the worktree, a removed line is in
;; the base, a context line is in both and the live file wins.
;; `nitpick-visit-other' opens the other one.  So no hunk shape can put a side
;; out of reach: the pair is total where magit's `magit-diff-visit-file' alone
;; leaves a green-only hunk with no way back to the base.

(defun nitpick--visit-parent-ranges (section)
  "Return SECTION's ranges, one per parent, or nil for a plain hunk.
magit keeps them in the hunk's `from-range' slot, as a list of ranges where a
plain hunk holds one range - and leaves the `from-ranges' slot its own line
counting reads empty, which is why that counting cannot be used here."
  (let ((from (nitpick--oref section 'from-range)))
    (and (consp (car from)) from)))

(defun nitpick--visit-combined-columns (section)
  "Return how many parent columns SECTION's lines carry, or nil for a plain diff.
A combined diff prefixes each line with one column per parent, which is also
what tells a line apart from the parent it belongs to."
  (and (nitpick--oref section 'combined)
       (let ((ranges (nitpick--visit-parent-ranges section)))
         (and ranges (length ranges)))))

(defun nitpick--visit-line-side ()
  "Return which version the line at point belongs to.

`new' for an added line, `old' for a removed one, and `both' for a context
line, a hunk heading, or anywhere outside a hunk - everything that exists on
either side, where the caller picks.

In a combined diff, (parent . N) for the parent a line is the other side of,
N counting from 1.  Each column says what the line is to that parent: a
space that it has it, a `+' that it does not, a `-' that it has it and the
result does not.  So all spaces is context, all pluses is a line only the
result has - a conflict marker, most of the time - and a column that differs
from the rest is the parent the line came from."
  (let ((section (magit-diff--hunk-section)))
    (if (null section)
        'both
      (let ((columns (nitpick--visit-combined-columns section))
            (bol (line-beginning-position)))
        (if (null columns)
            (pcase (char-after bol)
              (?+ 'new)
              (?- 'old)
              (_ 'both))
          (let ((prefix (buffer-substring-no-properties
                         bol (min (point-max) (+ bol columns)))))
            (cond
             ;; Only this parent has it, and the result does not.
             ((string-match "-" prefix) (cons 'parent (1+ (match-beginning 0))))
             ;; Every parent has it.
             ((not (string-search "+" prefix)) 'both)
             ;; The result and some of the parents: the ones that have it are
             ;; where it came from.  A conflicted worktree holds both sides
             ;; and the markers, so this is the usual shape there.
             ((string-match " " prefix) (cons 'parent (1+ (match-beginning 0))))
             ;; The result alone.
             (t 'new))))))))

(defun nitpick--visit-complement (side)
  "Return the side `nitpick-visit-other' opens when the point is on SIDE.
The other one, which for a combined diff's parent line is the conflicted file
itself - the one place all of the parents are visible at once."
  (pcase side
    ('old 'new)
    (`(parent . ,_) 'new)
    (_ 'old)))

(defun nitpick--visit-conflict-rev (n file)
  "Return the version of combined parent N for FILE, or of the base for 0.

A conflicted worktree keeps the three of them in the index, as stages 1 to 3,
and those are read as the objects they are.  A merge commit names its parents
instead, and its base is their merge base - a combined diff of either draws
no column for it."
  (if (length> (magit--file-index-stages file) 1)
      (format ":%d" (1+ n))
    (and magit-buffer-revision
         (if (> n 0)
             (format "%s^%d" magit-buffer-revision n)
           (magit-git-string "merge-base"
                             (format "%s^1" magit-buffer-revision)
                             (format "%s^2" magit-buffer-revision))))))

(defun nitpick--visit-target (side)
  "Return (REV FILE) naming the version SIDE holds of the file at point.
Nil when there is no such version to name.  `magit-diff-visit--sides' answers
for the two plain sides - `nitpick-diff-visit-base-mode' is what makes it
answer at all for a diff of a bare revision - and a combined diff's parents
are read out of the index or off the merge commit."
  (pcase-let* ((`(,old ,new) (magit-diff-visit--sides))
               (section (magit-diff--hunk-section))
               (columns (and section (nitpick--visit-combined-columns section))))
    (pcase side
      ((and 'old (guard columns))
       (let ((rev (nitpick--visit-conflict-rev 0 (nth 1 new))))
         (and rev (list rev (nth 1 new)))))
      ('old old)
      (`(parent . ,n)
       (let ((rev (nitpick--visit-conflict-rev n (nth 1 new))))
         (and rev (list rev (nth 1 new)))))
      (_ new))))

(defun nitpick--visit-exists-p (rev file)
  "Whether FILE has a version in REV at all.
What decides whether a side can be opened or has to fall back to the other:
an added file has nothing in the base, a deleted one nothing on disk."
  (and rev file
       (cond ((equal rev "{worktree}")
              (file-exists-p (expand-file-name file (magit-toplevel))))
             ((equal rev "{index}")
              (and (magit--file-index-stages file) t))
             ((nitpick--visit-stage rev)
              (and (nitpick--visit-stage-entry (nitpick--visit-stage rev) file) t))
             (t (and (magit-rev-verify (concat rev ":" file)) t)))))

(defun nitpick--visit-goto-first-change (section)
  "Put point on the first changed line of SECTION, if point is above its body.
`magit-diff-hunk-line' counts the lines the point follows, and from a heading
it leaves the point inside the first changed line rather than at its start -
which counts that line too, and lands the base a line past its own change.
Nothing moves when the point is already on a line of the hunk."
  (let ((content (nitpick--oref section 'content)))
    (when (and content (< (point) content))
      (goto-char content)
      (when (re-search-forward "^[-+]" nil t)
        (goto-char (line-beginning-position))))))

(defun nitpick--visit-line (side)
  "Return the line SIDE holds the point's line as, or nil.
Both plain sides are counted for any line of a hunk, so a removed line maps
to the line that now sits in its place and an added one to where it was
inserted.  A combined diff is counted per column; its base has no column, so
there is nothing to map and the file opens at the top."
  (and-let* ((section (magit-diff--hunk-section)))
    (let ((columns (nitpick--visit-combined-columns section)))
      (save-excursion
        (nitpick--visit-goto-first-change section)
        (pcase side
          ((guard (not columns)) (magit-diff-hunk-line section (eq side 'old)))
          ;; A combined diff draws no column for the base, so there is no
          ;; line of it to map the point to.
          ('old nil)
          (_ (nitpick--visit-combined-line section side)))))))

(defun nitpick--visit-combined-line (section side)
  "Return the line the point has on SIDE of combined SECTION.
SIDE is (parent . N) for one parent's own numbering, or anything else for the
result's.  A parent holds every line whose own column is not a `+'; the
result holds every line with no `-' in any column.  So the offset from the
start of that side's range is how many of its lines the point follows."
  (save-excursion
    (let* ((content (nitpick--oref section 'content))
           (columns (length (nitpick--visit-parent-ranges section)))
           (column (and (eq (car-safe side) 'parent) (1- (cdr side))))
           (start (if column
                      (car (nth column (nitpick--visit-parent-ranges section)))
                    (car (nitpick--oref section 'to-range))))
           (target (max (line-beginning-position) content))
           (offset 0))
      (goto-char content)
      (while (< (point) target)
        (let ((prefix (buffer-substring-no-properties
                       (point) (min (point-max) (+ (point) columns)))))
          (when (if column
                    (not (eq (aref prefix column) ?+))
                  (not (string-search "-" prefix)))
            (setq offset (1+ offset))))
        (forward-line))
      (and start (+ start offset)))))

(defun nitpick--visit-stage (rev)
  "Return the index stage REV names, or nil when it names something else."
  (and (stringp rev)
       (string-match "\\`:\\([0-9]\\)\\'" rev)
       (string-to-number (match-string 1 rev))))

(defun nitpick--visit-stage-entry (stage file)
  "Return FILE's index entry for STAGE, or nil."
  (seq-find (lambda (entry)
              (equal (car (split-string (nth 2 entry) "\t"))
                     (number-to-string stage)))
            (magit--file-index-stages file)))

(defun nitpick--visit-stage-noselect (stage file)
  "Return a read-only buffer of what index STAGE holds for FILE.

Read here rather than through `magit-find-file-noselect', which answers a
stage with an empty buffer: it takes the contents from the revision of the
buffer it made, and a stage is not one.  Named the way magit names a blob
buffer, so a conflict's three sides read as what they are."
  (let* ((buffer (get-buffer-create
                  (format "%s.~:%d~" (file-name-nondirectory file) stage)))
         (root (magit-toplevel))
         (text (with-temp-buffer
                 (let ((default-directory root))
                   (magit-git-insert "cat-file" "-p"
                                     (format ":%d:%s" stage file)))
                 (buffer-substring-no-properties (point-min) (point-max)))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (goto-char (point-min)))
      (setq-local default-directory root)
      ;; The file's own mode, without visiting it: `buffer-file-name' would
      ;; make this buffer look like the worktree file to everything that saves.
      (let ((buffer-file-name (expand-file-name file root)))
        (set-auto-mode))
      (setq buffer-read-only t))
    buffer))

(defun nitpick--visit-noselect (side)
  "Return (BUFFER POSITION) for the file at point as SIDE holds it.
POSITION is nil when the side holds no line to go to."
  (pcase-let* ((`(,rev ,file) (nitpick--visit-target side))
               (stage (nitpick--visit-stage rev))
               (buffer (if stage
                           (nitpick--visit-stage-noselect stage file)
                         (magit-find-file-noselect rev file)))
               (line (nitpick--visit-line side)))
    (list buffer
          (and line
               (with-current-buffer buffer
                 (save-restriction
                   (widen)
                   (goto-char (point-min))
                   (forward-line (1- line))
                   (point)))))))

(defun nitpick--visit-fallback (side)
  "Return the side to open instead of SIDE, and say why, or nil to refuse.
Never a dead keystroke: a side the file has no version in opens the side it
has, because that is the only thing the key can mean."
  (let ((other (nitpick--visit-complement side)))
    (pcase-let ((`(,rev ,file) (nitpick--visit-target other)))
      (and (nitpick--visit-exists-p rev file) other))))

(defun nitpick--visit-note (side fallback rev)
  "Return what to say when SIDE was asked for and FALLBACK opened instead."
  (format "%s; showing %s"
          (pcase side
            ('old "not in the base")
            (`(parent . ,n) (format "not in parent %d" n))
            (_ "not in the worktree"))
          (pcase fallback
            ('old (format "it as %s had it" rev))
            (_ "the file itself"))))

(defun nitpick--visit-side (side &optional display)
  "Visit the file at point as SIDE holds it, and return its buffer.
DISPLAY is `magit-diff-visit-file--internal' display argument: nil for this
window, t for another one, a function to call with the buffer."
  (unless (derived-mode-p 'magit-diff-mode 'magit-status-mode 'magit-revision-mode)
    (user-error "Not in a diff"))
  (pcase-let* ((`(,rev ,file) (nitpick--visit-target side))
               (asked side)
               (note nil))
    (unless (nitpick--visit-exists-p rev file)
      (let ((fallback (nitpick--visit-fallback side)))
        (unless fallback
          (user-error "No version of %s to open" (or file "this file")))
        (setq side fallback)
        (pcase-setq `(,rev ,file) (nitpick--visit-target side))
        (setq note (nitpick--visit-note asked side rev))))
    (pcase-let ((`(,buffer ,pos) (nitpick--visit-noselect side)))
      (pcase display
        ('nil (pop-to-buffer-same-window buffer))
        ('t (switch-to-buffer-other-window buffer))
        (_ (funcall display buffer)))
      (magit-diff-visit-file--setup buffer pos)
      (when note
        (message "%s: %s" file note))
      buffer)))

;;;###autoload
(defun nitpick-visit (&optional arg)
  "Visit the file at point as the version the line belongs to holds it.

An added line is in the worktree, a removed line is in the base, and a
context line is in both - where the worktree wins, since that is the file
you edit.  In a combined diff a line marked against one parent opens that
parent.  Outside a hunk there is no line to belong anywhere, so the worktree
opens at the file's first change.

`nitpick-visit-other' is the same keystroke for the other side, so nothing
about the shape of a hunk can put a version out of reach.  A side the file
has no version in - the base of a file this review added, the worktree of
one it deleted - opens the side it has, and says so.

With a prefix ARG, pick the version by name instead."
  (interactive "P")
  (if arg
      (nitpick-visit-pick)
    (nitpick--visit-side (nitpick--visit-line-side))))

;;;###autoload
(defun nitpick-visit-other (&optional arg)
  "Visit the file at point as the version the line does not belong to holds it.
The other side from `nitpick-visit': the base from an added or context line,
the worktree from a removed one, and the conflicted file itself from a
combined diff's parent line.  With a prefix ARG, pick by name."
  (interactive "P")
  (if arg
      (nitpick-visit-pick)
    (nitpick--visit-side (nitpick--visit-complement (nitpick--visit-line-side)))))

(defun nitpick--visit-candidates ()
  "Return an alist of (LABEL . SIDE) for every version the point can open."
  (let ((section (magit-diff--hunk-section)))
    (seq-filter
     (lambda (candidate)
       (pcase-let ((`(,rev ,file) (nitpick--visit-target (cdr candidate))))
         (nitpick--visit-exists-p rev file)))
     (append
      (list (cons "worktree" 'new) (cons "base" 'old))
      (and section
           (let ((columns (nitpick--visit-combined-columns section)))
             (and columns
                  (seq-map (lambda (n)
                             (cons (format "parent %d%s" n
                                           (pcase n
                                             (1 " (ours)")
                                             (2 " (theirs)")
                                             (_ "")))
                                   (cons 'parent n)))
                           (number-sequence 1 columns)))))))))

;;;###autoload
(defun nitpick-visit-pick ()
  "Visit the file at point as a version picked by name.
The way to the versions no line belongs to: the base of a conflict, or the
parent a combined diff does not mark the line against."
  (interactive)
  (let* ((candidates (nitpick--visit-candidates))
         (label (completing-read "Visit this file as: " candidates nil t)))
    (nitpick--visit-side (cdr (assoc label candidates)))))

;;;; Visiting the base's own blob from a diff

(defun nitpick--diff-visit-sides (sides)
  "Fill in the old side of SIDES when the diff left it blank.

`magit-diff-visit--sides' works the two sides of a diff out of the range its
buffer holds, through `magit-split-range', which answers nil for a range with
no separator in it: a bare revision, compared against the worktree.  Both
sides then come out nil, which resolves to the worktree, so RET on a removed
line opens the file as it is now - where that line is gone - instead of the
blob that still has it.

That is every diff nitpick opens, and magit's own `magit-diff-range' on a
single revision.  Here the sides are known: the revision on the left, the
worktree on the right, which is what the pane lists and what diff-hl paints.

Only that case.  Both revisions nil, a committed diff, and a range that
resolves to a revision of its own - so a commit, a stash, staged, unstaged,
and every two-dot range are left to magit."
  (pcase sides
    (`((nil ,old-file) (nil ,new-file))
     (let ((rev (and (derived-mode-p 'magit-diff-mode)
                     (eq magit-buffer-diff-type 'committed)
                     (stringp magit-buffer-diff-range)
                     magit-buffer-diff-range)))
       (if (and rev (magit-rev-verify rev))
           (list (list rev old-file) (list "{worktree}" new-file))
         sides)))
    (_ sides)))

;;;###autoload
(define-minor-mode nitpick-diff-visit-base-mode
  "Open the base's blob with RET on a removed line, not the file as it is now.

In a diff of one revision against the worktree - what the changed-file pane
shows, and `nitpick-diff-buffer-file' - magit cannot work out the old side and
visits the worktree from either side of a hunk.  So a removed line, the one
place the file on disk cannot answer for, opened the file without it.

Magit does this correctly for a commit, a stash, staged and unstaged changes,
and two-dot ranges; this fills in the one shape it has no sides for.
`C-<return>' (`magit-diff-visit-worktree-file') is still the worktree from
anywhere in the hunk."
  :global t
  :group 'nitpick
  (if nitpick-diff-visit-base-mode
      (advice-add 'magit-diff-visit--sides :filter-return
                  #'nitpick--diff-visit-sides)
    (advice-remove 'magit-diff-visit--sides #'nitpick--diff-visit-sides)))

(defun nitpick-diff-hl--repaint (proj)
  "Redraw diff-hl in PROJ's file buffers, or every file buffer when PROJ is nil.
diff-hl's own setters update each buffer after changing the reference, but
those updates write their git diffs into two buffers with fixed names, so
several in a row overwrite each other's results and the fringe stays as it
was.  Which is why a base set on a project with more than one buffer open
only showed up after the next save or revert.

Synchronously, one buffer at a time, for that same reason.  On an idle timer
so the command that set the base returns first."
  (run-with-idle-timer
   0 nil
   (lambda ()
     (dolist (buf (if proj (project-buffers proj) (buffer-list)))
       (when (buffer-live-p buf)
         (with-current-buffer buf
           (when (and (buffer-file-name) (bound-and-true-p diff-hl-mode))
             (let ((diff-hl-update-async nil)) (diff-hl-update)))))))))

(defun nitpick-diff-hl--root (root)
  "Return ROOT in the one spelling the base-ref cache is keyed by."
  (file-name-as-directory (expand-file-name root)))

(defun nitpick--nearest-branch (candidates main)
  "Return the branch in CANDIDATES whose merge base sits closest to HEAD.
CANDIDATES is a list of (BRANCH . DISTANCE), DISTANCE being the number of
commits between that branch's merge base with HEAD and HEAD itself.  The
smallest one is the branch HEAD most recently left: in a stack the parent's
own tip is that merge base, so the parent wins over what it was branched from.

MAIN wins a tie.  A branch merged with a fast-forward leaves its tip exactly
at the fork point it shares with MAIN, which ties, and would otherwise be
picked over MAIN on nothing but the order branches are listed in."
  (let (best best-distance)
    (dolist (candidate candidates)
      (let ((branch (car candidate))
            (distance (cdr candidate)))
        (when (or (null best-distance)
                  (< distance best-distance)
                  (and (= distance best-distance) (equal branch main)))
          (setq best branch
                best-distance distance))))
    best))

(defun nitpick--base-candidates (main)
  "Return (BRANCH . DISTANCE) for each local branch HEAD could have left.
Branches already merged into MAIN are left out, MAIN itself excepted: they
are finished work, and a fast-forward merge leaves one sitting exactly on a
fork point where it would outrank MAIN.  So is anything HEAD is an ancestor
of, which is a branch built on this one rather than the one under it."
  (let* ((head (magit-get-current-branch))
         (head-rev (magit-rev-parse "HEAD"))
         (merged (and main (magit-git-lines "branch" "--format=%(refname:short)"
                                            "--merged" main))))
    (delq nil
          (mapcar
           (lambda (branch)
             (unless (or (equal branch head)
                         (and (not (equal branch main)) (member branch merged)))
               (let ((base (magit-git-string "merge-base" "HEAD" branch)))
                 (and base
                      (not (equal base head-rev))
                      (cons branch
                            (string-to-number
                             (or (magit-git-string "rev-list" "--count"
                                                   (concat base "..HEAD"))
                                 "0")))))))
           (magit-list-local-branch-names)))))

(defun nitpick--nearest-base (root)
  "Return the revision ROOT's branch was most likely made from, or nil.
The nearest ancestor branch with `...' appended, so what is compared is what
this branch changed since it left that one - the forge's own \"Files
changed\", and the answer wanted when reviewing a branch rather than catching
up with where its base has gone since.

Nil on the main branch itself and on a detached HEAD: neither was made from
anything, so there is nothing to infer and the caller falls back."
  (let* ((default-directory root)
         (main (nitpick-diff-hl--default-base root))
         (head (magit-get-current-branch)))
    (cond
     ((or (null head) (null main) (equal head main)) nil)
     ;; Already merged: it has nothing of its own left, so compare against
     ;; main and let the answer be the empty diff that it is.
     ((magit-git-success "merge-base" "--is-ancestor" head main)
      (concat main nitpick--merge-base-suffix))
     (t (let ((nearest (nitpick--nearest-branch (nitpick--base-candidates main) main)))
          (and nearest (concat nearest nitpick--merge-base-suffix)))))))

(defun nitpick-diff-hl--suggested-base (root)
  "Return the revision to preselect when asking what to diff ROOT against.
In order: this worktree's last answer; the open PR's base, as the remote has
it, which is the forge's own view; the nearest ancestor branch, worked out
from the commit graph by `nitpick--nearest-base'; else ROOT's default branch
as the remote has it.

The forge comes before the graph because it knows the answer while the graph
only has evidence for it.  The graph comes before the remote's default branch
because it is right about a stack, and because a remote-tracking ref is only
as current as the last fetch.

Nil when none of them can be worked out: the prompt still opens, it just
suggests nothing."
  (or (alist-get (nitpick-diff-hl--root root) nitpick-diff-hl--bases nil nil #'string-equal)
      (let ((branch (ignore-errors (alist-get 'base (nitpick--pr-ctx root)))))
        (and branch (let ((default-directory root))
                      (concat (nitpick--remote) "/" branch))))
      (nitpick--nearest-base root)
      (let ((branch (nitpick-diff-hl--default-base root)))
        (and branch (let ((default-directory root))
                      (concat (nitpick--remote) "/" branch))))))

(defun nitpick-diff-hl--default-base (root)
  "Return ROOT's default branch, or nil.
`magit-main-branch' first, then the remote's HEAD - that ref is written at
clone time and is absent from plenty of clones."
  (let* ((default-directory root)
         (remote (nitpick--remote))
         (head (magit-git-string "symbolic-ref" "--short"
                                 (format "refs/remotes/%s/HEAD" remote))))
    (or (and (fboundp 'magit-main-branch) (magit-main-branch))
        (and head (string-remove-prefix (concat remote "/") head)))))

;;;###autoload
(defun nitpick-diff-hl-set-from-pullreq (worktree-path pullreq)
  "Point diff-hl at PULLREQ's merge-base for the WORKTREE-PATH project.
Thin wrapper over `nitpick-diff-hl-set-base' that reads the base branch from
the Forge PULLREQ object.  The worktree files then show exactly what the PR
changed while LSP and jump-to-definition keep working on the real files."
  ;; Slot name via a variable: a literal makes the byte-compiler check it
  ;; against Forge classes it cannot see at build time.
  (let* ((slot 'base-ref)
         (default-directory worktree-path))
    (nitpick-diff-hl-set-base
     worktree-path (concat (nitpick--remote) "/" (eieio-oref pullreq slot)))))

;;;; Forge integration

(defun nitpick--maybe-submit-via-forge (event orig-fun args)
  "Submit the pending review with EVENT, else call ORIG-FUN with ARGS."
  (let* ((root (ignore-errors (magit-toplevel)))
         (rid (and root
                   (ignore-errors
                     (let ((default-directory root))
                       (nitpick--pending-review (alist-get 'id (nitpick--pr-ctx root))))))))
    (if rid
        (nitpick-submit event)
      (apply orig-fun args))))

(defun nitpick--forge-approve-advice (orig-fun &rest args)
  "Route `forge-approve-pullreq' (ORIG-FUN, ARGS) through the batch submitter."
  (nitpick--maybe-submit-via-forge 'approve orig-fun args))

(defun nitpick--forge-request-changes-advice (orig-fun &rest args)
  "Route `forge-request-changes' (ORIG-FUN, ARGS) through the batch submitter."
  (nitpick--maybe-submit-via-forge 'request-changes orig-fun args))

;;;###autoload
(define-minor-mode nitpick-forge-mode
  "Submit pending reviews through Forge's own approve / request-changes.
Advises the public commands, and falls back to Forge's native (comment-less)
behaviour when there is no pending review."
  :global t
  :group 'nitpick
  (if nitpick-forge-mode
      (progn
        (advice-add 'forge-approve-pullreq :around #'nitpick--forge-approve-advice)
        (advice-add 'forge-request-changes :around #'nitpick--forge-request-changes-advice))
    (advice-remove 'forge-approve-pullreq #'nitpick--forge-approve-advice)
    (advice-remove 'forge-request-changes #'nitpick--forge-request-changes-advice)))

;;;; Keymap

;;;###autoload
;; `nitpick-tree' lives in its own feature, autoloaded: the pane needs treemacs
;; and most of a review does not.
(declare-function nitpick-tree "nitpick-tree" (root revision))

(defvar nitpick-prefix-map
  (let ((map (make-sparse-keymap)))
    (define-key map "c" #'nitpick-comment)
    (define-key map "l" #'nitpick-list)
    (define-key map "s" #'nitpick-submit)
    (define-key map "f" #'nitpick-refresh)
    (define-key map "b" #'nitpick-diff-hl-set-base)
    (define-key map "H" #'nitpick-diff-hl-line-mode)
    (define-key map "t" #'nitpick-tree)
    (define-key map "d" #'nitpick-diff-buffer-file)
    map)
  "Keymap of PR review commands, meant to be bound to a prefix key.")

(defvar nitpick-mode-map (make-sparse-keymap)
  "Keymap for `nitpick-mode'.
`nitpick-keymap-prefix' is installed into it; the mode only decides whether
the binding is live, so nothing is touched globally while it is off.")

(defvar nitpick--installed-prefix nil
  "The prefix currently bound in `nitpick-mode-map', or nil.")

;; The option and its setter refer to each other, and a warning fails the
;; build, so declare the variable before the function reads it.
(defvar nitpick-keymap-prefix)

(defun nitpick--install-prefix ()
  "Bind `nitpick-keymap-prefix' to `nitpick-prefix-map' in `nitpick-mode-map'.
Removes the prefix an earlier call installed, so setting the option twice
does not leave the old key behind."
  (when nitpick--installed-prefix
    (keymap-unset nitpick-mode-map nitpick--installed-prefix t)
    (setq nitpick--installed-prefix nil))
  (when nitpick-keymap-prefix
    (keymap-set nitpick-mode-map nitpick-keymap-prefix nitpick-prefix-map)
    (setq nitpick--installed-prefix nitpick-keymap-prefix)))

(defcustom nitpick-keymap-prefix "C-c v"
  "Prefix key that `nitpick-mode' binds `nitpick-prefix-map' to.
Set it to nil to have `nitpick-mode' bind nothing, and bind
`nitpick-prefix-map' wherever you like instead."
  :type '(choice (key :tag "Prefix key")
                 (const :tag "None" nil))
  :group 'nitpick
  :set (lambda (symbol value)
         (set-default symbol value)
         (nitpick--install-prefix)))

;; The default value of a defcustom does not run :set, so install it once here.
(nitpick--install-prefix)

;;;###autoload
(define-minor-mode nitpick-mode
  "Put the PR review commands on `nitpick-keymap-prefix'.
Default bindings are opt-in: enable this mode to take them, or leave it
off and bind `nitpick-prefix-map' yourself."
  :global t
  :group 'nitpick
  :keymap nitpick-mode-map)

(provide 'nitpick)
;;; nitpick.el ends here
