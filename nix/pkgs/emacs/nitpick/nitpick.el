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
(declare-function magit-read-branch-or-commit "magit-git" (prompt &optional secondary-default exclude))
(declare-function magit-run-git "magit-process" (&rest args))
(declare-function forge--get-remote "forge-repo" (&optional remote))
(declare-function diff-hl-set-reference-rev "diff-hl" (rev))
(declare-function diff-hl-set-reference-rev-in-project-internal "diff-hl" (rev project))
(declare-function diff-hl-highlight-on-fringe "diff-hl" (ovl type shape))
(declare-function diff-hl-highlight-on-fringe-flat "diff-hl" (ovl type shape))
(declare-function diff-hl-update "diff-hl" ())
(declare-function diff-hl-changes-buffer "diff-hl" (file backend &optional new-rev bufname))
(declare-function project-buffers "project" (project))
(defvar diff-hl-mode)
(defvar diff-hl-reference-revision)
(defvar diff-hl-update-async)
(defvar vc-git-diff-switches)
(defvar diff-hl-highlight-function)
(defvar diff-hl-highlight-reference-function)
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

(defun nitpick--add-thread (review-id path line start-line body)
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
    (nitpick--graphql q vars)))

;;;; Commands

;;;###autoload
(defun nitpick-comment (beg end)
  "Add an inline review comment on the current file's line(s) as a draft.
It is saved to your pending review immediately (created if needed), so it is
server-side and crash-safe.  Publish the whole review later via
`nitpick-submit' or Forge's approve / request-changes.  With an active region,
target the line range BEG..END; otherwise the current line.

The line(s) must be part of the PR's diff (a changed line, or context inside a
hunk); the forge rejects anything outside it."
  (interactive
   (if (use-region-p) (list (region-beginning) (region-end))
     (list (line-beginning-position) (line-end-position))))
  (nitpick--gh)
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
         (buf (get-buffer-create "*nitpick-comment*")))
    (with-current-buffer buf
      (erase-buffer)
      (when (fboundp 'gfm-mode) (gfm-mode))
      (setq nitpick--comment-ctx
            (list (cons 'root root) (cons 'path path)
                  (cons 'line end-line) (cons 'start-line (and multi start-line))))
      (setq header-line-format
            (format " Draft PR comment on %s:%s  -  C-c C-c add - C-c C-k cancel"
                    path (if multi (format "%d-%d" start-line end-line)
                           (number-to-string end-line))))
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
       (alist-get 'path ctx) (alist-get 'line ctx) (alist-get 'start-line ctx) body)
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

(defcustom nitpick-diff-hl-line-faces
  '((insert . nitpick-diff-hl-line-insert)
    (change . nitpick-diff-hl-line-change))
  "Face per diff-hl change type.  A type absent here keeps the fringe only.
`delete' is absent on purpose: the overlay sits on the line after the removed
text, so painting it would mark a line the PR never touched."
  :type '(alist :key-type symbol :value-type face)
  :group 'nitpick)

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

(defun nitpick-diff-hl-highlight-line-flat (ovl type shape)
  "Highlight OVL as diff-hl would, then paint its whole line.
For the reference-revision pass; TYPE and SHAPE are diff-hl's."
  (funcall (nitpick-diff-hl--inner t) ovl type shape)
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

(defun nitpick--diff-hl-advise ()
  "Put `nitpick--zero-context' around diff-hl's diff, at most once."
  (advice-add 'diff-hl-changes-buffer :around #'nitpick--zero-context))

;;;###autoload
(define-minor-mode nitpick-diff-hl-zero-context-mode
  "Correct the lines diff-hl marks, by forcing `-U0' on the diffs it parses.
Off, the fringe and the painted lines can sit above the change they belong
to.  A workaround for the build, not for diff-hl's design; it goes when the
binding reaches git on its own."
  :global t
  :group 'nitpick
  (if nitpick-diff-hl-zero-context-mode
      ;; Only once diff-hl is loaded.  This mode is turned on from a config
      ;; file, where diff-hl is usually still waiting to be autoloaded, and
      ;; advice put on it before that does not survive its load: the advice
      ;; is still listed afterwards and never runs again.
      (if (featurep 'diff-hl)
          (nitpick--diff-hl-advise)
        (eval-after-load 'diff-hl
          (lambda ()
            (when nitpick-diff-hl-zero-context-mode (nitpick--diff-hl-advise)))))
    (advice-remove 'diff-hl-changes-buffer #'nitpick--zero-context)))

;;;; diff-hl: annotate the worktree with the PR's own changes

;;;###autoload
(defun nitpick-diff-hl-set-base (root revision)
  "Diff the ROOT project against REVISION instead of its checked-out state.

REVISION is used as picked - a local branch, a remote-tracking ref like
`origin/master', a tag, a sha.  Nothing is prefixed for you, so `master' and
`origin/master' are different answers.  Pick HEAD for the usual view of your
own uncommitted edits.

What lands in diff-hl is the merge-base of REVISION and HEAD, a 3-dot diff
like the forge's \"Files changed\": for a revision already in your history that
is the revision itself, and for a divergent ref it keeps other people's
commits out of your fringe.  Set project-locally, so newly opened files
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
             (rev (or (magit-git-string "merge-base" revision "HEAD")
                      (magit-rev-verify revision)))
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
          (diff-hl-set-reference-rev-in-project-internal rev proj)
          (nitpick-diff-hl--repaint proj)
          (message "diff-hl: %s now shows changes vs %s (%s)"
                   (file-name-nondirectory (directory-file-name root))
                   revision (magit-rev-abbrev rev)))
         ((fboundp 'diff-hl-set-reference-rev)
          ;; Older diff-hl without per-project references: fall back to global.
          (funcall remember)
          (diff-hl-set-reference-rev rev)
          (nitpick-diff-hl--repaint nil)
          (message "diff-hl: showing changes vs %s (%s) [global]"
                   revision (magit-rev-abbrev rev)))))
    (error
     (message "diff-hl base not set: %s" (error-message-string err)))))

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

(defun nitpick-diff-hl--suggested-base (root)
  "Return the revision to preselect when asking what to diff ROOT against.
This worktree's last answer, else the open PR's base, else ROOT's default
branch - the last two as the remote has them, which is the forge's own view
of the branch.  Nil when none of the three can be worked out: the prompt
still opens, it just suggests nothing."
  (or (alist-get (nitpick-diff-hl--root root) nitpick-diff-hl--bases nil nil #'string-equal)
      (let ((branch (or (ignore-errors (alist-get 'base (nitpick--pr-ctx root)))
                        (nitpick-diff-hl--default-base root))))
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
(defvar nitpick-prefix-map
  (let ((map (make-sparse-keymap)))
    (define-key map "c" #'nitpick-comment)
    (define-key map "l" #'nitpick-list)
    (define-key map "s" #'nitpick-submit)
    (define-key map "f" #'nitpick-refresh)
    (define-key map "b" #'nitpick-diff-hl-set-base)
    (define-key map "H" #'nitpick-diff-hl-line-mode)
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
