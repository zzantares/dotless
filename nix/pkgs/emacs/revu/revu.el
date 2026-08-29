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
;; `revu-refresh'.  Bind them yourself, or bind `revu-prefix-map'.
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
(declare-function magit-rev-abbrev "magit-git" (rev))
(declare-function magit-run-git "magit-process" (&rest args))
(declare-function forge--get-remote "forge-repo" (&optional remote))
(declare-function diff-hl-set-reference-rev "diff-hl" (rev))
(declare-function diff-hl-set-reference-rev-in-project-internal "diff-hl" (rev project))
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

;;;; diff-hl: annotate the worktree with the PR's own changes

;;;###autoload
(defun revu-diff-hl-set-base (root base-ref)
  "Point diff-hl at the merge-base of BASE-REF and HEAD for the ROOT project.

BASE-REF is a branch name like \"master\"; the reference revision is
`<remote>/BASE-REF' merge-based with HEAD (a 3-dot diff, like the forge's \"Files
changed\").  Set project-locally so it does not bleed into other projects, and
newly opened files inherit it."
  (condition-case err
      (let* ((default-directory root)
             (base (concat (or (and (fboundp 'forge--get-remote) (forge--get-remote))
                               "origin")
                           "/" base-ref))
             (rev (or (magit-git-string "merge-base" base "HEAD")
                      (magit-rev-verify base)))
             (proj (project-current nil root)))
        (cond
         ((not rev)
          (message "diff-hl: could not resolve PR base %s" base))
         ((and proj (fboundp 'diff-hl-set-reference-rev-in-project-internal))
          (diff-hl-set-reference-rev-in-project-internal rev proj)
          (message "diff-hl: %s now shows PR changes vs %s (%s)"
                   (file-name-nondirectory (directory-file-name root))
                   base (magit-rev-abbrev rev)))
         ((fboundp 'diff-hl-set-reference-rev)
          ;; Older diff-hl without per-project references: fall back to global.
          (diff-hl-set-reference-rev rev)
          (message "diff-hl: showing PR changes vs %s (%s) [global]"
                   base (magit-rev-abbrev rev)))))
    (error
     (message "diff-hl PR reference not set: %s" (error-message-string err)))))

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
    map)
  "Keymap of PR review commands, meant to be bound to a prefix key.")

(provide 'revu)
;;; revu.el ends here
