;;; revu.el --- Batched pull request reviews from Emacs -*- lexical-binding: t; -*-

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
;; Commands: `revu-comment', `revu-list', `revu-submit',
;; `revu-refresh'.  `revu-mode' puts them on `revu-keymap-prefix' (C-c v by
;; default); leave it off to bind `revu-prefix-map' yourself.
;;
;; GitHub via the `gh' CLI is the only backend today; the public names are
;; backend-neutral so another forge can be added behind them.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'project)

(declare-function magit-toplevel "magit-git" (&optional directory))
(declare-function magit-file-relative-name "magit-git" (&optional file tracked))
(declare-function magit-git-string "magit-git" (&rest args))
(declare-function magit-rev-verify "magit-git" (rev))
(declare-function magit-main-branch "magit-git" ())
(declare-function magit-rev-abbrev "magit-git" (rev))
(declare-function magit-run-git "magit-process" (&rest args))
(declare-function forge--get-remote "forge-repo" (&optional remote))
(declare-function diff-hl-set-reference-rev "diff-hl" (rev))
(declare-function diff-hl-set-reference-rev-in-project-internal "diff-hl" (rev project))
(declare-function diff-hl-reset-reference-rev "diff-hl" (&optional global))
(declare-function diff-hl-highlight-on-fringe "diff-hl" (ovl type shape))
(declare-function diff-hl-highlight-on-fringe-flat "diff-hl" (ovl type shape))
(declare-function diff-hl-update "diff-hl" ())
(defvar diff-hl-mode)
(defvar diff-hl-reference-revision)
(defvar diff-hl-highlight-function)
(defvar diff-hl-highlight-reference-function)
(declare-function projectile-invalidate-cache "projectile" (prompt))
(declare-function eieio-oref "eieio-core" (obj slot))

(defgroup revu nil
  "Batched pull request reviews from the files on disk."
  :group 'tools
  :prefix "revu-")

(defcustom revu-gh-executable "gh"
  "The `gh' CLI used to talk to GitHub.  Nix pins this to a store path."
  :type 'string
  :group 'revu)

(defun revu--gh ()
  "Return the usable `gh' executable, or signal a user error."
  (or (if (file-name-absolute-p revu-gh-executable)
          (and (file-executable-p revu-gh-executable) revu-gh-executable)
        (executable-find revu-gh-executable))
      (user-error "The `gh' CLI is not available (see `revu-gh-executable')")))

(defun revu--remote ()
  "Return the git remote to resolve branches against."
  (or (and (fboundp 'forge--get-remote) (forge--get-remote)) "origin"))

(defvar-local revu--comment-ctx nil
  "Context alist for the inline PR comment being composed.")
(defvar-local revu--submit-ctx nil
  "Context alist (root, review, event, number) for a review being submitted.")

;;;; Backend: GitHub GraphQL over the `gh' CLI

(defun revu--graphql (query variables)
  "Run GraphQL QUERY with VARIABLES (an alist) via `gh'; return the `data' alist.
Arrays parse to lists, objects to alists.  Signals an error on transport failure
or a GraphQL `errors' array (gh returns those with a non-zero exit)."
  (let ((gh (revu--gh))
        (payload (json-encode `((query . ,query)
                                (variables . ,(or variables (make-hash-table))))))
        (out (generate-new-buffer " *revu-graphql*")))
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

(defun revu--pr-ctx (&optional root)
  "Return an alist of PR context for ROOT (default `magit-toplevel').
Keys: `id' (node id), `number', `base' (base branch), `head' (head SHA).
Errors if the current branch has no associated open PR."
  (let* ((default-directory (or root (magit-toplevel)
                                (user-error "Not inside a git repository")))
         (out (generate-new-buffer " *revu-pr-view*")))
    (unwind-protect
        (if (/= 0 (call-process (revu--gh) nil out nil "pr" "view"
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

(defun revu--pending-review (pr-id)
  "Return the viewer's pending review node id for PR-ID, or nil.
Pending reviews are private to their author, so states:[PENDING] returns only
our own."
  (let* ((q "query($pr:ID!){ node(id:$pr){ ... on PullRequest {
               reviews(first:20, states:[PENDING]){ nodes { id } } } } }")
         (data (revu--graphql q `((pr . ,pr-id))))
         (nodes (alist-get 'nodes (alist-get 'reviews (alist-get 'node data)))))
    (alist-get 'id (car nodes))))

(defun revu--ensure-review (pr-id head)
  "Return the viewer's pending review id for PR-ID, creating one pinned to HEAD."
  (or (revu--pending-review pr-id)
      (let* ((q "mutation($pr:ID!,$oid:GitObjectID!){
                   addPullRequestReview(input:{pullRequestId:$pr, commitOID:$oid}){
                     pullRequestReview { id } } }")
             (data (revu--graphql q `((pr . ,pr-id) (oid . ,head)))))
        (alist-get 'id (alist-get 'pullRequestReview
                                  (alist-get 'addPullRequestReview data))))))

(defun revu--add-thread (review-id path line start-line body)
  "Add a RIGHT-side draft thread to REVIEW-ID at PATH.
It covers LINE, or the range START-LINE..LINE when START-LINE differs."
  (let* ((range (and start-line (/= start-line line)))
         (q (if range
                "mutation($r:ID!,$p:String!,$b:String!,$l:Int!,$s:Int!){
                   addPullRequestReviewThread(input:{pullRequestReviewId:$r,path:$p,
                     body:$b,line:$l,side:RIGHT,startLine:$s,startSide:RIGHT}){
                     thread { id } } }"
              "mutation($r:ID!,$p:String!,$b:String!,$l:Int!){
                   addPullRequestReviewThread(input:{pullRequestReviewId:$r,path:$p,
                     body:$b,line:$l,side:RIGHT}){ thread { id } } }"))
         (vars (append `((r . ,review-id) (p . ,path) (b . ,body) (l . ,line))
                       (when range `((s . ,start-line))))))
    (revu--graphql q vars)))

;;;; Commands

;;;###autoload
(defun revu-comment (beg end)
  "Add an inline review comment on the current file's line(s) as a draft.
It is saved to your pending review immediately (created if needed), so it is
server-side and crash-safe.  Publish the whole review later via
`revu-submit' or Forge's approve / request-changes.  With an active region,
target the line range BEG..END; otherwise the current line.

The line(s) must be part of the PR's diff (a changed line, or context inside a
hunk); the forge rejects anything outside it."
  (interactive
   (if (use-region-p) (list (region-beginning) (region-end))
     (list (line-beginning-position) (line-end-position))))
  (revu--gh)
  (unless buffer-file-name (user-error "Buffer is not visiting a file"))
  (when (buffer-modified-p)
    (user-error "Save the buffer first: line numbers must match the PR head"))
  (let* ((root (or (magit-toplevel) (user-error "Not inside a git repository")))
         (path (or (magit-file-relative-name buffer-file-name)
                   (user-error "File is not inside the repository")))
         (start-line (line-number-at-pos beg))
         (end-line (save-excursion
                     (goto-char end)
                     (when (and (> end beg) (bolp)) (backward-char))
                     (line-number-at-pos)))
         (multi (/= start-line end-line))
         (buf (get-buffer-create "*revu-comment*")))
    (with-current-buffer buf
      (erase-buffer)
      (when (fboundp 'gfm-mode) (gfm-mode))
      (setq revu--comment-ctx
            (list (cons 'root root) (cons 'path path)
                  (cons 'line end-line) (cons 'start-line (and multi start-line))))
      (setq header-line-format
            (format " Draft PR comment on %s:%s  -  C-c C-c add - C-c C-k cancel"
                    path (if multi (format "%d-%d" start-line end-line)
                           (number-to-string end-line))))
      (local-set-key (kbd "C-c C-c") #'revu--comment-add)
      (local-set-key (kbd "C-c C-k") #'revu-cancel))
    (pop-to-buffer buf)
    (message "Write your comment, then C-c C-c to add it to the pending review")))

;;;###autoload
(defun revu-cancel ()
  "Abort the comment / review composer."
  (interactive)
  (let ((b (current-buffer))) (quit-window) (kill-buffer b)))

(defun revu--comment-add ()
  "Add the composed comment as a draft thread on the PR's pending review."
  (interactive)
  (let* ((ctx revu--comment-ctx)
         (body (string-trim (buffer-substring-no-properties (point-min) (point-max))))
         (default-directory (alist-get 'root ctx)))
    (when (string-empty-p body) (user-error "Comment body is empty"))
    (let* ((pr (revu--pr-ctx default-directory))
           (local (string-trim (shell-command-to-string "git rev-parse HEAD"))))
      (when (and (stringp (alist-get 'head pr))
                 (not (string-prefix-p local (alist-get 'head pr)))
                 (not (string-prefix-p (alist-get 'head pr) local)))
        (message "Warning: worktree HEAD differs from PR head - run `revu-refresh'"))
      (revu--add-thread
       (revu--ensure-review (alist-get 'id pr) (alist-get 'head pr))
       (alist-get 'path ctx) (alist-get 'line ctx) (alist-get 'start-line ctx) body)
      (let ((b (current-buffer))) (quit-window) (kill-buffer b))
      (message "Added draft comment to pending review of PR #%s" (alist-get 'number pr)))))

;;;###autoload
(defun revu-list ()
  "List the draft comments in this PR's pending review, read live from the forge."
  (interactive)
  (let* ((root (or (magit-toplevel) (user-error "Not inside a git repository")))
         (default-directory root)
         (pr (revu--pr-ctx root))
         (rid (revu--pending-review (alist-get 'id pr))))
    (unless rid (user-error "No pending review for PR #%s" (alist-get 'number pr)))
    (let* ((q "query($r:ID!){ node(id:$r){ ... on PullRequestReview {
                 comments(first:100){ nodes { path line startLine outdated body } } } } }")
           (items (alist-get 'nodes (alist-get 'comments
                    (alist-get 'node (revu--graphql q `((r . ,rid)))))))
           (buf (get-buffer-create "*revu*")))
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
(defun revu-submit (&optional event)
  "Submit this PR's pending review.
EVENT is `comment' (default), `approve', or `request-changes'.  Opens a composer
for the summary body; C-c C-c publishes all draft comments together with the
verdict."
  (interactive)
  (let* ((event (or event 'comment))
         (root (or (magit-toplevel) (user-error "Not inside a git repository")))
         (default-directory root)
         (pr (revu--pr-ctx root))
         (rid (revu--pending-review (alist-get 'id pr)))
         (gh-event (pcase event
                     ('approve "APPROVE") ('request-changes "REQUEST_CHANGES") (_ "COMMENT"))))
    (unless rid (user-error "No pending review to submit for PR #%s" (alist-get 'number pr)))
    (let ((buf (get-buffer-create "*revu-submit*")))
      (with-current-buffer buf
        (erase-buffer)
        (when (fboundp 'gfm-mode) (gfm-mode))
        (setq revu--submit-ctx
              (list (cons 'root root) (cons 'review rid)
                    (cons 'event gh-event) (cons 'number (alist-get 'number pr))))
        (setq header-line-format
              (format " Submit %s review of PR #%s  -  C-c C-c publish - C-c C-k cancel"
                      gh-event (alist-get 'number pr)))
        (local-set-key (kbd "C-c C-c") #'revu--submit-send)
        (local-set-key (kbd "C-c C-k") #'revu-cancel))
      (pop-to-buffer buf)
      (message "Optional summary, then C-c C-c to publish the %s review" gh-event))))

(defun revu--submit-send ()
  "Publish the pending review with the chosen event and summary body."
  (interactive)
  (let* ((ctx revu--submit-ctx)
         (body (string-trim (buffer-substring-no-properties (point-min) (point-max))))
         (default-directory (alist-get 'root ctx))
         (q "mutation($r:ID!,$e:PullRequestReviewEvent!,$b:String){
               submitPullRequestReview(input:{pullRequestReviewId:$r,event:$e,body:$b}){
                 pullRequestReview { url state } } }")
         (vars (append `((r . ,(alist-get 'review ctx)) (e . ,(alist-get 'event ctx)))
                       (unless (string-empty-p body) `((b . ,body)))))
         (data (revu--graphql q vars))
         (url (alist-get 'url (alist-get 'pullRequestReview
                                         (alist-get 'submitPullRequestReview data))))
         (b (current-buffer)))
    (quit-window)
    (kill-buffer b)
    (message "Submitted %s review of PR #%s%s"
             (alist-get 'event ctx) (alist-get 'number ctx)
             (if url (concat ": " url) ""))))

;;;###autoload
(defun revu-refresh ()
  "Resync the worktree and diff-hl to the PR's latest head, report stale drafts.
Run after the author pushes new commits mid-review.  Aborts if the worktree has
uncommitted changes (a review worktree should have none)."
  (interactive)
  (let* ((root (or (magit-toplevel) (user-error "Not inside a git repository")))
         (default-directory root))
    (unless (string-empty-p (string-trim (shell-command-to-string "git status --porcelain")))
      (user-error "Worktree has local changes; commit or stash before refreshing"))
    (let* ((pr (revu--pr-ctx root))
           (new-head (alist-get 'head pr)))
      (magit-run-git "fetch")
      (magit-run-git "reset" "--hard" new-head)
      (when (fboundp 'projectile-invalidate-cache) (projectile-invalidate-cache nil))
      (revu-diff-hl-set-base root (alist-get 'base pr))
      (let ((rid (revu--pending-review (alist-get 'id pr))))
        (if (not rid)
            (message "Resynced PR #%s to %s (no pending review)"
                     (alist-get 'number pr) (substring new-head 0 7))
          (let* ((q "query($r:ID!){ node(id:$r){ ... on PullRequestReview {
                       comments(first:100){ nodes { outdated } } } } }")
                 (items (alist-get 'nodes (alist-get 'comments
                          (alist-get 'node (revu--graphql q `((r . ,rid)))))))
                 (n-out (seq-count (lambda (c) (eq t (alist-get 'outdated c))) items)))
            (message "Resynced PR #%s to %s - %d/%d draft comment(s) now outdated%s"
                     (alist-get 'number pr) (substring new-head 0 7)
                     n-out (length items)
                     (if (> n-out 0) " (`revu-list' to review)" ""))))))))

;;;; diff-hl: paint the changed lines, not only the fringe

(defface revu-diff-hl-line-insert
  '((((background dark))  :extend t :background "#1e2d1e")
    (((background light)) :extend t :background "#e3f7e3"))
  "Background for whole lines the PR adds."
  :group 'revu)

(defface revu-diff-hl-line-change
  '((((background dark))  :extend t :background "#20293d")
    (((background light)) :extend t :background "#e0e8ff"))
  "Background for whole lines the PR modifies."
  :group 'revu)

(defcustom revu-diff-hl-line-faces
  '((insert . revu-diff-hl-line-insert)
    (change . revu-diff-hl-line-change))
  "Face per diff-hl change type.  A type absent here keeps the fringe only.
`delete' is absent on purpose: the overlay sits on the line after the removed
text, so painting it would mark a line the PR never touched."
  :type '(alist :key-type symbol :value-type face)
  :group 'revu)

(defcustom revu-diff-hl-line-priority -60
  "Overlay priority of the line backgrounds.
Below `hl-line''s -50, so the cursor line keeps its own colour."
  :type 'integer
  :group 'revu)

(defcustom revu-diff-hl-line-highlight t
  "Whether `revu-diff-hl-set-base' also turns on `revu-diff-hl-line-mode'."
  :type 'boolean
  :group 'revu)

(defvar revu-diff-hl--bases nil
  "Alist of (ROOT . BASE-REF) last pointed at by `revu-diff-hl-set-base'.
A memo that outlives the view being switched off, so `revu-diff-hl-toggle'
can switch it back on without asking the forge for the base branch again.")

(defvar revu-diff-hl--pointed nil
  "Roots whose diff-hl currently points at a PR base rather than HEAD.")

(defvar revu-diff-hl--saved nil
  "The two diff-hl highlight functions `revu-diff-hl-line-mode' replaced.
A cons of the working-tree one and the reference one.  Kept so the mode
delegates to them instead of assuming fringes, and puts them back on exit.")

(defun revu-diff-hl--inner (reference)
  "Return the highlight function wrapped for the REFERENCE or working pass."
  (or (if reference (cdr revu-diff-hl--saved) (car revu-diff-hl--saved))
      (if reference #'diff-hl-highlight-on-fringe-flat #'diff-hl-highlight-on-fringe)))

(defun revu-diff-hl--paint-line (ovl type)
  "Stretch OVL over its whole line and paint it for diff-hl's TYPE.
Point is at the start of the line diff-hl is highlighting.  The trailing
newline is included so the `:extend' faces reach the window edge."
  (if-let* ((face (alist-get type revu-diff-hl-line-faces)))
      (progn
        (move-overlay ovl (line-beginning-position)
                      (min (point-max) (1+ (line-end-position))))
        (overlay-put ovl 'face face)
        (overlay-put ovl 'priority revu-diff-hl-line-priority))
    ;; diff-hl recycles overlays between its two passes; clear a stale face.
    (overlay-put ovl 'face nil)))

(defun revu-diff-hl-highlight-line (ovl type shape)
  "Highlight OVL as diff-hl would, then paint its whole line.
For the working-tree pass; TYPE and SHAPE are diff-hl's."
  (funcall (revu-diff-hl--inner nil) ovl type shape)
  (revu-diff-hl--paint-line ovl type))

(defun revu-diff-hl-highlight-line-flat (ovl type shape)
  "Highlight OVL as diff-hl would, then paint its whole line.
For the reference-revision pass; TYPE and SHAPE are diff-hl's."
  (funcall (revu-diff-hl--inner t) ovl type shape)
  (revu-diff-hl--paint-line ovl type))

(defun revu-diff-hl--redraw ()
  "Rebuild the diff-hl overlays of every buffer that has them."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (bound-and-true-p diff-hl-mode) (diff-hl-update)))))

;;;###autoload
(define-minor-mode revu-diff-hl-line-mode
  "Show diff-hl changes as whole-line backgrounds, not just fringe marks.

Both of diff-hl's highlight slots are swapped: `diff-hl-highlight-function'
for working-tree changes and `diff-hl-highlight-reference-function' for
changes against the reference revision.  Reviewing a PR goes through the
second one, so setting only the first would leave the PR's own lines bare.

Whatever those slots held still runs, so the fringe or margin marks stay."
  :global t
  :group 'revu
  (if revu-diff-hl-line-mode
      (progn
        (unless revu-diff-hl--saved
          (setq revu-diff-hl--saved (cons diff-hl-highlight-function
                                          diff-hl-highlight-reference-function)))
        (setq diff-hl-highlight-function #'revu-diff-hl-highlight-line
              diff-hl-highlight-reference-function #'revu-diff-hl-highlight-line-flat))
    (when revu-diff-hl--saved
      (setq diff-hl-highlight-function (car revu-diff-hl--saved)
            diff-hl-highlight-reference-function (cdr revu-diff-hl--saved)
            revu-diff-hl--saved nil)))
  (revu-diff-hl--redraw))

;;;; diff-hl: annotate the worktree with the PR's own changes

;;;###autoload
(defun revu-diff-hl-set-base (root base-ref)
  "Point diff-hl at the merge-base of BASE-REF and HEAD for the ROOT project.

BASE-REF is a branch name like \"master\"; the reference revision is
`<remote>/BASE-REF' merge-based with HEAD (a 3-dot diff, like the forge's \"Files
changed\").  Set project-locally so it does not bleed into other projects, and
newly opened files inherit it.

Also turns on `revu-diff-hl-line-mode' unless `revu-diff-hl-line-highlight'
is nil; `revu-diff-hl-reset' undoes both."
  (condition-case err
      (let* ((default-directory root)
             (base (concat (revu--remote) "/" base-ref))
             (rev (or (magit-git-string "merge-base" base "HEAD")
                      (magit-rev-verify base)))
             (proj (project-current nil root)))
        (cond
         ((not rev)
          (message "diff-hl: could not resolve PR base %s" base))
         ((and proj (fboundp 'diff-hl-set-reference-rev-in-project-internal))
          (setf (alist-get (revu-diff-hl--root root) revu-diff-hl--bases
                           nil nil #'string-equal)
                base-ref)
          (cl-pushnew (revu-diff-hl--root root) revu-diff-hl--pointed
                      :test #'string-equal)
          (when revu-diff-hl-line-highlight (revu-diff-hl-line-mode 1))
          (diff-hl-set-reference-rev-in-project-internal rev proj)
          (message "diff-hl: %s now shows PR changes vs %s (%s)"
                   (file-name-nondirectory (directory-file-name root))
                   base (magit-rev-abbrev rev)))
         ((fboundp 'diff-hl-set-reference-rev)
          ;; Older diff-hl without per-project references: fall back to global.
          (setf (alist-get (revu-diff-hl--root root) revu-diff-hl--bases
                           nil nil #'string-equal)
                base-ref)
          (cl-pushnew (revu-diff-hl--root root) revu-diff-hl--pointed
                      :test #'string-equal)
          (when revu-diff-hl-line-highlight (revu-diff-hl-line-mode 1))
          (diff-hl-set-reference-rev rev)
          (message "diff-hl: showing PR changes vs %s (%s) [global]"
                   base (magit-rev-abbrev rev)))))
    (error
     (message "diff-hl PR reference not set: %s" (error-message-string err)))))

;;;###autoload
(defun revu-diff-hl-toggle ()
  "Toggle the review view of the worktree at point.

On: diff-hl points at the PR's base, so the fringe and - unless
`revu-diff-hl-line-highlight' is nil - the lines themselves show what the PR
changed.  Off: diff-hl goes back to HEAD and stops painting lines.

The base branch comes from the last `revu-diff-hl-set-base' for this
worktree, else the open PR, else the repository's default branch - so this
works on a branch with no PR yet."
  (interactive)
  (let ((root (or (magit-toplevel) (user-error "Not inside a git repository"))))
    (if (revu-diff-hl--active-p root)
        (revu-diff-hl--reset root)
      (revu-diff-hl-set-base root (revu-diff-hl--base-ref root)))))

(defun revu-diff-hl--root (root)
  "Return ROOT in the one spelling the base-ref cache is keyed by."
  (file-name-as-directory (expand-file-name root)))

(defun revu-diff-hl--active-p (root)
  "Whether diff-hl is pointed somewhere other than HEAD for ROOT."
  (or (and (member (revu-diff-hl--root root) revu-diff-hl--pointed) t)
      ;; set by hand, or in a buffer opened after the project was pointed
      (and (bound-and-true-p diff-hl-reference-revision) t)))

(defun revu-diff-hl--base-ref (root)
  "Return the base branch to diff ROOT against.
This worktree's last base, else the open PR's, else ROOT's default branch.
The PR is only where a base is written down; a branch without one still gets
an answer, while a stacked or release-targeting PR still needs the forge."
  (or (alist-get (revu-diff-hl--root root) revu-diff-hl--bases nil nil #'string-equal)
      (ignore-errors (alist-get 'base (revu--pr-ctx root)))
      (revu-diff-hl--default-base root)
      (user-error "No open PR and no default branch to diff against")))

(defun revu-diff-hl--default-base (root)
  "Return ROOT's default branch, or nil.
`magit-main-branch' first, then the remote's HEAD - that ref is written at
clone time and is absent from plenty of clones."
  (let* ((default-directory root)
         (remote (revu--remote))
         (head (magit-git-string "symbolic-ref" "--short"
                                 (format "refs/remotes/%s/HEAD" remote))))
    (or (and (fboundp 'magit-main-branch) (magit-main-branch))
        (and head (string-remove-prefix (concat remote "/") head)))))

(defun revu-diff-hl--reset (root)
  "Point diff-hl back at HEAD for ROOT and stop painting whole lines."
  (setq revu-diff-hl--pointed
        (delete (revu-diff-hl--root root) revu-diff-hl--pointed))
  (when (fboundp 'diff-hl-reset-reference-rev)
    ;; the prefix argument also discards diff-hl's per-project references,
    ;; which is where `revu-diff-hl-set-base' put ours
    (diff-hl-reset-reference-rev '(4)))
  (revu-diff-hl-line-mode -1)
  (message "diff-hl: back to HEAD"))

;;;###autoload
(defun revu-diff-hl-set-from-pullreq (worktree-path pullreq)
  "Point diff-hl at PULLREQ's merge-base for the WORKTREE-PATH project.
Thin wrapper over `revu-diff-hl-set-base' that reads the base branch from
the Forge PULLREQ object.  The worktree files then show exactly what the PR
changed while LSP and jump-to-definition keep working on the real files."
  ;; Slot name via a variable: a literal makes the byte-compiler check it
  ;; against Forge classes it cannot see at build time.
  (let ((slot 'base-ref))
    (revu-diff-hl-set-base worktree-path (eieio-oref pullreq slot))))

;;;; Forge integration

(defun revu--maybe-submit-via-forge (event orig-fun args)
  "Submit the pending review with EVENT, else call ORIG-FUN with ARGS."
  (let* ((root (ignore-errors (magit-toplevel)))
         (rid (and root
                   (ignore-errors
                     (let ((default-directory root))
                       (revu--pending-review (alist-get 'id (revu--pr-ctx root))))))))
    (if rid
        (revu-submit event)
      (apply orig-fun args))))

(defun revu--forge-approve-advice (orig-fun &rest args)
  "Route `forge-approve-pullreq' (ORIG-FUN, ARGS) through the batch submitter."
  (revu--maybe-submit-via-forge 'approve orig-fun args))

(defun revu--forge-request-changes-advice (orig-fun &rest args)
  "Route `forge-request-changes' (ORIG-FUN, ARGS) through the batch submitter."
  (revu--maybe-submit-via-forge 'request-changes orig-fun args))

;;;###autoload
(define-minor-mode revu-forge-mode
  "Submit pending reviews through Forge's own approve / request-changes.
Advises the public commands, and falls back to Forge's native (comment-less)
behaviour when there is no pending review."
  :global t
  :group 'revu
  (if revu-forge-mode
      (progn
        (advice-add 'forge-approve-pullreq :around #'revu--forge-approve-advice)
        (advice-add 'forge-request-changes :around #'revu--forge-request-changes-advice))
    (advice-remove 'forge-approve-pullreq #'revu--forge-approve-advice)
    (advice-remove 'forge-request-changes #'revu--forge-request-changes-advice)))

;;;; Keymap

;;;###autoload
(defvar revu-prefix-map
  (let ((map (make-sparse-keymap)))
    (define-key map "c" #'revu-comment)
    (define-key map "l" #'revu-list)
    (define-key map "s" #'revu-submit)
    (define-key map "f" #'revu-refresh)
    (define-key map "h" #'revu-diff-hl-toggle)
    map)
  "Keymap of PR review commands, meant to be bound to a prefix key.")

(defvar revu-mode-map (make-sparse-keymap)
  "Keymap for `revu-mode'.
`revu-keymap-prefix' is installed into it; the mode only decides whether
the binding is live, so nothing is touched globally while it is off.")

(defvar revu--installed-prefix nil
  "The prefix currently bound in `revu-mode-map', or nil.")

;; The option and its setter refer to each other, and a warning fails the
;; build, so declare the variable before the function reads it.
(defvar revu-keymap-prefix)

(defun revu--install-prefix ()
  "Bind `revu-keymap-prefix' to `revu-prefix-map' in `revu-mode-map'.
Removes the prefix an earlier call installed, so setting the option twice
does not leave the old key behind."
  (when revu--installed-prefix
    (keymap-unset revu-mode-map revu--installed-prefix t)
    (setq revu--installed-prefix nil))
  (when revu-keymap-prefix
    (keymap-set revu-mode-map revu-keymap-prefix revu-prefix-map)
    (setq revu--installed-prefix revu-keymap-prefix)))

(defcustom revu-keymap-prefix "C-c v"
  "Prefix key that `revu-mode' binds `revu-prefix-map' to.
Set it to nil to have `revu-mode' bind nothing, and bind
`revu-prefix-map' wherever you like instead."
  :type '(choice (key :tag "Prefix key")
                 (const :tag "None" nil))
  :group 'revu
  :set (lambda (symbol value)
         (set-default symbol value)
         (revu--install-prefix)))

;; The default value of a defcustom does not run :set, so install it once here.
(revu--install-prefix)

;;;###autoload
(define-minor-mode revu-mode
  "Put the PR review commands on `revu-keymap-prefix'.
Default bindings are opt-in: enable this mode to take them, or leave it
off and bind `revu-prefix-map' yourself."
  :global t
  :group 'revu
  :keymap revu-mode-map)

(provide 'revu)
;;; revu.el ends here
