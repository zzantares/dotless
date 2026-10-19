;;; revu-test.el --- Tests for revu -*- lexical-binding: t; -*-

;;; Commentary:

;; Hermetic ERT suite: no network, no `gh', no magit, no forge.  Stubs stand in
;; for the process boundary and record what would have been sent, so the tests
;; assert on the GraphQL query and variables rather than on a live PR.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'revu)

;;;; Stub helper

(defun revu-test--call-with-stubs (stubs thunk)
  "Install STUBS, an alist of (SYMBOL . FUNCTION), around THUNK.
Symbols that were unbound are made unbound again afterwards, so stubbing
magit or forge does not leave definitions behind."
  (let ((saved (mapcar (lambda (s)
                         (cons (car s)
                               (and (fboundp (car s)) (symbol-function (car s)))))
                       stubs)))
    (unwind-protect
        (progn (dolist (s stubs) (fset (car s) (cdr s)))
               (funcall thunk))
      (dolist (s saved)
        (if (cdr s) (fset (car s) (cdr s)) (fmakunbound (car s)))))))

(defmacro revu-test--with-stubs (bindings &rest body)
  "Evaluate BODY with BINDINGS, a list of (SYMBOL FUNCTION), installed."
  (declare (indent 1) (debug ((&rest (symbolp form)) body)))
  `(revu-test--call-with-stubs
    (list ,@(mapcar (lambda (b) `(cons ',(car b) ,(cadr b))) bindings))
    (lambda () ,@body)))

(defvar revu-test--payload nil
  "Stdin handed to the last stubbed `call-process-region'.")

(defun revu-test--stdin-stub (exit json)
  "Return a `call-process-region' stub answering JSON and exiting with EXIT."
  (lambda (beg end _program &optional _delete buffer &rest _args)
    (setq revu-test--payload (buffer-substring-no-properties beg end))
    (when (bufferp buffer)
      (with-current-buffer buffer (insert json)))
    exit))

(defun revu-test--process-stub (exit json)
  "Return a `call-process' stub answering JSON and exiting with EXIT."
  (lambda (_program &optional _infile destination &rest _args)
    (when (bufferp destination)
      (with-current-buffer destination (insert json)))
    exit))

(defun revu-test--recorder (result)
  "Return a `revu--graphql' stub that records into a cons and returns RESULT."
  (let ((cell (cons nil nil)))
    (cons cell (lambda (query variables)
                 (setcar cell query)
                 (setcdr cell variables)
                 result))))

;;;; `gh' resolution

(ert-deftest revu-test-gh-absolute-path-must-be-executable ()
  "An absolute `revu-gh-executable' is used only when it is executable."
  (let ((exe (make-temp-file "revu-gh")))
    (unwind-protect
        (let ((revu-gh-executable exe))
          (set-file-modes exe #o755)
          (should (equal (revu--gh) exe))
          (set-file-modes exe #o644)
          (should-error (revu--gh) :type 'user-error))
      (delete-file exe))))

(ert-deftest revu-test-gh-relative-name-goes-through-path ()
  (revu-test--with-stubs
      ((executable-find (lambda (n &rest _) (and (equal n "gh") "/usr/bin/gh"))))
    (let ((revu-gh-executable "gh"))
      (should (equal (revu--gh) "/usr/bin/gh")))))

(ert-deftest revu-test-gh-missing-signals-user-error ()
  "A missing CLI is a user error, not a crash inside `call-process'."
  (revu-test--with-stubs
      ((executable-find (lambda (&rest _) nil)))
    (let ((revu-gh-executable "not-on-path"))
      (should-error (revu--gh) :type 'user-error))))

;;;; GraphQL transport

(ert-deftest revu-test-graphql-returns-the-data-alist ()
  (revu-test--with-stubs
      ((revu--gh (lambda () "/bin/true"))
       (call-process-region
        (revu-test--stdin-stub 0 "{\"data\":{\"node\":{\"id\":\"R_1\"}}}")))
    (let ((data (revu--graphql "query{}" nil)))
      (should (equal (alist-get 'id (alist-get 'node data)) "R_1")))))

(ert-deftest revu-test-graphql-sends-query-and-variables-on-stdin ()
  (setq revu-test--payload nil)
  (revu-test--with-stubs
      ((revu--gh (lambda () "/bin/true"))
       (call-process-region (revu-test--stdin-stub 0 "{\"data\":{}}")))
    (revu--graphql "query($x:ID!){ node(id:$x){ id } }" '((x . "PR_1"))))
  (let ((sent (json-parse-string revu-test--payload :object-type 'alist)))
    (should (equal (alist-get 'query sent) "query($x:ID!){ node(id:$x){ id } }"))
    (should (equal (alist-get 'x (alist-get 'variables sent)) "PR_1"))))

(ert-deftest revu-test-graphql-reports-the-forge-error-message ()
  "A GraphQL `errors' array must surface its message, not the raw buffer."
  (revu-test--with-stubs
      ((revu--gh (lambda () "/bin/true"))
       (call-process-region
        (revu-test--stdin-stub
         1 "{\"errors\":[{\"message\":\"Could not resolve to a node\"}]}")))
    (let ((err (should-error (revu--graphql "q" nil))))
      (should (string-match-p "Could not resolve to a node"
                              (error-message-string err))))))

(ert-deftest revu-test-graphql-signals-on-unparseable-output ()
  (revu-test--with-stubs
      ((revu--gh (lambda () "/bin/true"))
       (call-process-region (revu-test--stdin-stub 1 "gh: command failed")))
    (should-error (revu--graphql "q" nil))))

(ert-deftest revu-test-graphql-does-not-leak-its-buffer ()
  "The work buffer is killed on the success and the failure path alike."
  (revu-test--with-stubs
      ((revu--gh (lambda () "/bin/true"))
       (call-process-region (revu-test--stdin-stub 0 "{\"data\":{}}")))
    (revu--graphql "q" nil))
  (should-not (get-buffer " *revu-graphql*"))
  (revu-test--with-stubs
      ((revu--gh (lambda () "/bin/true"))
       (call-process-region (revu-test--stdin-stub 1 "boom")))
    (ignore-errors (revu--graphql "q" nil)))
  (should-not (get-buffer " *revu-graphql*")))

;;;; PR context

(ert-deftest revu-test-pr-ctx-parses-gh-json ()
  (revu-test--with-stubs
      ((revu--gh (lambda () "/bin/true"))
       (call-process
        (revu-test--process-stub
         0 (concat "{\"id\":\"PR_1\",\"number\":97,"
                   "\"baseRefName\":\"master\",\"headRefOid\":\"abc123\"}"))))
    (let ((ctx (revu--pr-ctx "/tmp")))
      (should (equal (alist-get 'id ctx) "PR_1"))
      (should (equal (alist-get 'number ctx) 97))
      (should (equal (alist-get 'base ctx) "master"))
      (should (equal (alist-get 'head ctx) "abc123")))))

(ert-deftest revu-test-pr-ctx-errors-without-an-open-pr ()
  (revu-test--with-stubs
      ((revu--gh (lambda () "/bin/true"))
       (call-process (revu-test--process-stub 1 "no pull requests found")))
    (should-error (revu--pr-ctx "/tmp"))))

(ert-deftest revu-test-pr-ctx-does-not-leak-its-buffer ()
  (revu-test--with-stubs
      ((revu--gh (lambda () "/bin/true"))
       (call-process (revu-test--process-stub 1 "nope")))
    (ignore-errors (revu--pr-ctx "/tmp")))
  (should-not (get-buffer " *revu-pr-view*")))

;;;; Pending review discovery

(ert-deftest revu-test-pending-review-returns-the-first-node ()
  (revu-test--with-stubs
      ((revu--graphql
        (lambda (&rest _)
          '((node . ((reviews . ((nodes . (((id . "PRR_1")) ((id . "PRR_2"))))))))))))
    (should (equal (revu--pending-review "PR_1") "PRR_1"))))

(ert-deftest revu-test-pending-review-nil-when-none ()
  (revu-test--with-stubs
      ((revu--graphql (lambda (&rest _) '((node . ((reviews . ((nodes . nil))))))))) 
    (should-not (revu--pending-review "PR_1"))))

(ert-deftest revu-test-ensure-review-reuses-a-pending-review ()
  "Reusing must not issue a mutation: GitHub allows only one pending review."
  (let ((mutations 0))
    (revu-test--with-stubs
        ((revu--pending-review (lambda (_) "PRR_existing"))
         (revu--graphql (lambda (&rest _) (cl-incf mutations) nil)))
      (should (equal (revu--ensure-review "PR_1" "sha") "PRR_existing"))
      (should (= mutations 0)))))

(ert-deftest revu-test-ensure-review-creates-one-pinned-to-head ()
  (let* ((rec (revu-test--recorder
               '((addPullRequestReview . ((pullRequestReview . ((id . "PRR_new"))))))))
         (cell (car rec)))
    (revu-test--with-stubs
        ((revu--pending-review (lambda (_) nil))
         (revu--graphql (cdr rec)))
      (should (equal (revu--ensure-review "PR_1" "deadbeef") "PRR_new"))
      (should (string-match-p "addPullRequestReview" (car cell)))
      (should (equal (alist-get 'oid (cdr cell)) "deadbeef")))))

;;;; Draft threads

(ert-deftest revu-test-add-thread-single-line-omits-start-line ()
  (let* ((rec (revu-test--recorder nil))
         (cell (car rec)))
    (revu-test--with-stubs ((revu--graphql (cdr rec)))
      (revu--add-thread "PRR_1" "a/b.el" 42 nil "hi")
      (should-not (string-match-p "startLine" (car cell)))
      (should (equal (alist-get 'l (cdr cell)) 42))
      (should-not (assq 's (cdr cell))))))

(ert-deftest revu-test-add-thread-range-sends-start-line ()
  (let* ((rec (revu-test--recorder nil))
         (cell (car rec)))
    (revu-test--with-stubs ((revu--graphql (cdr rec)))
      (revu--add-thread "PRR_1" "a/b.el" 42 40 "hi")
      (should (string-match-p "startLine:\\$s" (car cell)))
      (should (equal (alist-get 's (cdr cell)) 40))
      (should (equal (alist-get 'l (cdr cell)) 42)))))

(ert-deftest revu-test-add-thread-collapses-a-degenerate-range ()
  "A one-line region is a single-line comment, not a 42..42 range."
  (let* ((rec (revu-test--recorder nil))
         (cell (car rec)))
    (revu-test--with-stubs ((revu--graphql (cdr rec)))
      (revu--add-thread "PRR_1" "a/b.el" 42 42 "hi")
      (should-not (string-match-p "startLine" (car cell)))
      (should-not (assq 's (cdr cell))))))

;;;; Comment composer

(defun revu-test--in-file-buffer (fn)
  "Call FN with (DIR FILE) inside a buffer visiting a file under a temp DIR."
  (let* ((dir (make-temp-file "revu-repo" t))
         (file (expand-file-name "src/thing.el" dir))
         buf)
    (unwind-protect
        (progn
          (make-directory (file-name-directory file) t)
          (with-temp-file file (insert "line1\nline2\nline3\n"))
          (setq buf (find-file-noselect file))
          (with-current-buffer buf (funcall fn dir file)))
      (when (buffer-live-p buf)
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf))
      (delete-directory dir t))))

(ert-deftest revu-test-comment-targets-the-current-line ()
  (revu-test--in-file-buffer
   (lambda (dir _file)
     (revu-test--with-stubs
         ((revu--gh (lambda () "/bin/true"))
          (magit-toplevel (lambda (&rest _) dir))
          (magit-file-relative-name (lambda (&rest _) "src/thing.el"))
          (pop-to-buffer (lambda (&rest _) nil)))
       (goto-char (point-min))
       (forward-line 1)
       (revu-comment (line-beginning-position) (line-end-position))
       (with-current-buffer "*revu-comment*"
         (should (equal (alist-get 'path revu--comment-ctx) "src/thing.el"))
         (should (equal (alist-get 'line revu--comment-ctx) 2))
         (should-not (alist-get 'start-line revu--comment-ctx)))))))

(ert-deftest revu-test-comment-region-ending-at-bol-drops-the-last-line ()
  "Selecting lines 1-2 leaves point at the start of line 3; that is not line 3."
  (revu-test--in-file-buffer
   (lambda (dir _file)
     (revu-test--with-stubs
         ((revu--gh (lambda () "/bin/true"))
          (magit-toplevel (lambda (&rest _) dir))
          (magit-file-relative-name (lambda (&rest _) "src/thing.el"))
          (pop-to-buffer (lambda (&rest _) nil)))
       (let ((beg (point-min))
             (end (save-excursion (goto-char (point-min)) (forward-line 2) (point))))
         (revu-comment beg end))
       (with-current-buffer "*revu-comment*"
         (should (equal (alist-get 'start-line revu--comment-ctx) 1))
         (should (equal (alist-get 'line revu--comment-ctx) 2)))))))

(ert-deftest revu-test-comment-refuses-an-unsaved-buffer ()
  "Line numbers are meaningless against the PR head if the buffer is dirty."
  (revu-test--in-file-buffer
   (lambda (dir _file)
     (revu-test--with-stubs
         ((revu--gh (lambda () "/bin/true"))
          (magit-toplevel (lambda (&rest _) dir))
          (magit-file-relative-name (lambda (&rest _) "src/thing.el")))
       (goto-char (point-max))
       (insert "dirty\n")
       (should-error (revu-comment (point-min) (point-max)) :type 'user-error)))))

(ert-deftest revu-test-comment-refuses-a-non-file-buffer ()
  (revu-test--with-stubs ((revu--gh (lambda () "/bin/true")))
    (with-temp-buffer
      (should-error (revu-comment (point-min) (point-max)) :type 'user-error))))

;;;; Submit

(ert-deftest revu-test-submit-maps-events-to-the-graphql-enum ()
  (dolist (case '((approve . "APPROVE")
                  (request-changes . "REQUEST_CHANGES")
                  (comment . "COMMENT")
                  (nil . "COMMENT")))
    (revu-test--with-stubs
        ((magit-toplevel (lambda (&rest _) "/tmp"))
         (revu--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 97))))
         (revu--pending-review (lambda (_) "PRR_1"))
         (pop-to-buffer (lambda (&rest _) nil)))
      (revu-submit (car case))
      (with-current-buffer "*revu-submit*"
        (should (equal (alist-get 'event revu--submit-ctx) (cdr case)))))))

(ert-deftest revu-test-submit-errors-without-a-pending-review ()
  (revu-test--with-stubs
      ((magit-toplevel (lambda (&rest _) "/tmp"))
       (revu--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 97))))
       (revu--pending-review (lambda (_) nil)))
    (should-error (revu-submit 'approve) :type 'user-error)))

(ert-deftest revu-test-submit-send-omits-an-empty-body ()
  "GitHub rejects an empty body string; the variable must be absent instead."
  (let* ((rec (revu-test--recorder
               '((submitPullRequestReview
                  . ((pullRequestReview . ((url . "https://example/1")
                                           (state . "APPROVED"))))))))
         (cell (car rec)))
    (revu-test--with-stubs
        ((revu--graphql (cdr rec))
         (quit-window (lambda (&rest _) nil)))
      (with-temp-buffer
        (setq revu--submit-ctx
              '((root . "/tmp") (review . "PRR_1") (event . "APPROVE") (number . 97)))
        (insert "   \n  ")
        (revu--submit-send))
      (should (equal (alist-get 'e (cdr cell)) "APPROVE"))
      (should (equal (alist-get 'r (cdr cell)) "PRR_1"))
      (should-not (assq 'b (cdr cell))))))

(ert-deftest revu-test-submit-send-passes-a-trimmed-body ()
  (let* ((rec (revu-test--recorder
               '((submitPullRequestReview
                  . ((pullRequestReview . ((url . "https://example/1")
                                           (state . "COMMENTED"))))))))
         (cell (car rec)))
    (revu-test--with-stubs
        ((revu--graphql (cdr rec))
         (quit-window (lambda (&rest _) nil)))
      (with-temp-buffer
        (setq revu--submit-ctx
              '((root . "/tmp") (review . "PRR_1") (event . "COMMENT") (number . 97)))
        (insert "\n  looks good  \n")
        (revu--submit-send))
      (should (equal (alist-get 'b (cdr cell)) "looks good")))))

;;;; Forge integration

(ert-deftest revu-test-forge-mode-adds-and-removes-its-advice ()
  (revu-test--with-stubs
      ((forge-approve-pullreq (lambda (&rest _) 'native))
       (forge-request-changes (lambda (&rest _) 'native)))
    (unwind-protect
        (progn
          (revu-forge-mode 1)
          (should (advice-member-p #'revu--forge-approve-advice
                                   'forge-approve-pullreq))
          (should (advice-member-p #'revu--forge-request-changes-advice
                                   'forge-request-changes))
          (revu-forge-mode -1)
          (should-not (advice-member-p #'revu--forge-approve-advice
                                       'forge-approve-pullreq))
          (should-not (advice-member-p #'revu--forge-request-changes-advice
                                       'forge-request-changes)))
      (revu-forge-mode -1))))

(ert-deftest revu-test-forge-falls-back-to-native-without-drafts ()
  "With no pending review, Forge's own body-only review must still work."
  (let (called)
    (revu-test--with-stubs
        ((magit-toplevel (lambda (&rest _) "/tmp"))
         (revu--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 1))))
         (revu--pending-review (lambda (_) nil))
         (revu-submit (lambda (&rest _) (setq called 'batched))))
      (revu--maybe-submit-via-forge
       'approve (lambda (&rest _) (setq called 'native)) nil)
      (should (eq called 'native)))))

(ert-deftest revu-test-forge-routes-to-the-batch-submitter-with-drafts ()
  (let (called)
    (revu-test--with-stubs
        ((magit-toplevel (lambda (&rest _) "/tmp"))
         (revu--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 1))))
         (revu--pending-review (lambda (_) "PRR_1"))
         (revu-submit (lambda (&rest _) (setq called 'batched))))
      (revu--maybe-submit-via-forge
       'approve (lambda (&rest _) (setq called 'native)) nil)
      (should (eq called 'batched)))))

(ert-deftest revu-test-forge-falls-back-outside-a-repository ()
  (let (called)
    (revu-test--with-stubs
        ((magit-toplevel (lambda (&rest _) nil))
         (revu-submit (lambda (&rest _) (setq called 'batched))))
      (revu--maybe-submit-via-forge
       'approve (lambda (&rest _) (setq called 'native)) nil)
      (should (eq called 'native)))))

;;;; diff-hl whole-line highlighting

;; diff-hl is not in scope at build time: revu.el only declares these two
;; variables special, so give them a dynamic binding to fake.
(defvar diff-hl-reference-revision nil)
(defvar diff-hl-highlight-function nil)
(defvar diff-hl-highlight-reference-function nil)

(defmacro revu-test--with-diff-hl (&rest body)
  "Run BODY with diff-hl's two highlight slots bound to recording stubs.
diff-hl is not in scope at build time, so the slots and the functions they
hold are faked; the suite asserts on the overlays revu produces."
  (declare (indent 0))
  `(let ((diff-hl-highlight-function 'revu-test--inner-working)
         (diff-hl-highlight-reference-function 'revu-test--inner-reference)
         (revu-diff-hl--saved nil)
         (revu-diff-hl--pointed nil)
         (revu-diff-hl-line-mode nil)
         (revu-test--inner-calls nil))
     (revu-test--with-stubs
         ((revu-test--inner-working
           (lambda (&rest args) (push (cons 'working args) revu-test--inner-calls)))
          (revu-test--inner-reference
           (lambda (&rest args) (push (cons 'reference args) revu-test--inner-calls)))
          (diff-hl-update (lambda () nil)))
       ,@body)))

(defvar revu-test--inner-calls nil
  "Calls recorded by the stubbed diff-hl highlight functions.")

(defun revu-test--line-overlay (line)
  "Return a zero-width overlay at the start of LINE, as diff-hl makes one."
  (goto-char (point-min))
  (forward-line (1- line))
  (make-overlay (point) (point)))

(defmacro revu-test--in-buffer (&rest body)
  "Run BODY in a three-line temp buffer."
  (declare (indent 0))
  `(with-temp-buffer
     (insert "alpha\nbeta\ngamma\n")
     ,@body))

(ert-deftest revu-test-diff-hl-paints-the-whole-line ()
  (revu-test--in-buffer
    (let ((ovl (revu-test--line-overlay 2)))
      (revu-diff-hl--paint-line ovl 'insert)
      ;; the span covers "beta" and its newline, so an `:extend' face reaches
      ;; the window edge
      (should (equal (buffer-substring-no-properties
                      (overlay-start ovl) (overlay-end ovl))
                     "beta\n"))
      (should (eq (overlay-get ovl 'face) 'revu-diff-hl-line-insert))
      (should (eq (overlay-get ovl 'priority) revu-diff-hl-line-priority)))))

(ert-deftest revu-test-diff-hl-paints-a-change-with-the-change-face ()
  (revu-test--in-buffer
    (let ((ovl (revu-test--line-overlay 1)))
      (revu-diff-hl--paint-line ovl 'change)
      (should (eq (overlay-get ovl 'face) 'revu-diff-hl-line-change)))))

(ert-deftest revu-test-diff-hl-leaves-deletions-to-the-fringe ()
  (revu-test--in-buffer
    (let ((ovl (revu-test--line-overlay 2)))
      ;; nothing was removed from the line the overlay sits on, so it must not
      ;; be painted, and must stay zero-width
      (revu-diff-hl--paint-line ovl 'delete)
      (should-not (overlay-get ovl 'face))
      (should (= (overlay-start ovl) (overlay-end ovl))))))

(ert-deftest revu-test-diff-hl-clears-a-recycled-overlay ()
  (revu-test--in-buffer
    (let ((ovl (revu-test--line-overlay 2)))
      (revu-diff-hl--paint-line ovl 'insert)
      (revu-diff-hl--paint-line ovl 'delete)
      (should-not (overlay-get ovl 'face)))))

(ert-deftest revu-test-diff-hl-last-line-without-a-newline ()
  (with-temp-buffer
    (insert "alpha\nomega")
    (let ((ovl (revu-test--line-overlay 2)))
      (revu-diff-hl--paint-line ovl 'insert)
      (should (= (overlay-end ovl) (point-max))))))

(ert-deftest revu-test-diff-hl-line-mode-swaps-both-slots ()
  (revu-test--with-diff-hl
    (revu-diff-hl-line-mode 1)
    (should (eq diff-hl-highlight-function #'revu-diff-hl-highlight-line))
    (should (eq diff-hl-highlight-reference-function
                #'revu-diff-hl-highlight-line-flat))))

(ert-deftest revu-test-diff-hl-line-mode-restores-both-slots ()
  (revu-test--with-diff-hl
    (revu-diff-hl-line-mode 1)
    (revu-diff-hl-line-mode 1)
    (revu-diff-hl-line-mode -1)
    (should (eq diff-hl-highlight-function 'revu-test--inner-working))
    (should (eq diff-hl-highlight-reference-function 'revu-test--inner-reference))
    (should-not revu-diff-hl--saved)))

(ert-deftest revu-test-diff-hl-line-mode-keeps-the-inner-highlighting ()
  (revu-test--with-diff-hl
    (revu-diff-hl-line-mode 1)
    (revu-test--in-buffer
      (let ((ovl (revu-test--line-overlay 2)))
        (funcall diff-hl-highlight-function ovl 'insert 'single)
        (funcall diff-hl-highlight-reference-function ovl 'insert 'single)
        (should (equal (mapcar #'car revu-test--inner-calls)
                       '(reference working)))
        (should (eq (overlay-get ovl 'face) 'revu-diff-hl-line-insert))))))

(defmacro revu-test--with-set-base (&rest body)
  "Run BODY with `revu-diff-hl-set-base' stubbed down to its own logic.
Magit, diff-hl and the project are faked; `revu-diff-hl--bases' starts empty."
  (declare (indent 0))
  `(revu-test--with-diff-hl
     (let ((revu-diff-hl--bases nil)
           (revu-test--pointed-at nil))
       (revu-test--with-stubs
           ((magit-toplevel (lambda (&optional _) "/tmp/wt/"))
            (magit-git-string (lambda (&rest _) "cafe1234"))
            (magit-rev-abbrev (lambda (_) "cafe123"))
            (project-current (lambda (&optional _ _) '(transient . "/tmp/wt/")))
            (diff-hl-set-reference-rev-in-project-internal
             (lambda (rev _proj) (setq revu-test--pointed-at rev)))
            (diff-hl-reset-reference-rev
             (lambda (&optional _) (setq revu-test--pointed-at nil))))
         ,@body))))

(defvar revu-test--pointed-at nil
  "Reference revision handed to the stubbed diff-hl.")

(ert-deftest revu-test-diff-hl-set-base-enables-the-line-mode ()
  (revu-test--with-set-base
    (let ((revu-diff-hl-line-highlight t))
      (revu-diff-hl-set-base "/tmp/wt/" "master")
      (should revu-diff-hl-line-mode))
    (revu-diff-hl-line-mode -1)
    (let ((revu-diff-hl-line-highlight nil))
      (revu-diff-hl-set-base "/tmp/wt/" "master")
      (should-not revu-diff-hl-line-mode))))

(ert-deftest revu-test-diff-hl-set-base-remembers-the-base-ref ()
  (revu-test--with-set-base
    (revu-diff-hl-set-base "/tmp/wt" "develop")
    ;; keyed by one spelling, so a root without the trailing slash still hits
    (should (equal (revu-diff-hl--base-ref "/tmp/wt/") "develop"))))

(ert-deftest revu-test-diff-hl-toggle-turns-the-review-view-off ()
  (revu-test--with-set-base
    (revu-diff-hl-set-base "/tmp/wt/" "master")
    (should (revu-diff-hl--active-p "/tmp/wt/"))
    (revu-diff-hl-toggle)
    (should-not revu-diff-hl-line-mode)
    (should-not revu-test--pointed-at)
    (should-not (revu-diff-hl--active-p "/tmp/wt/"))))

(ert-deftest revu-test-diff-hl-toggle-turns-it-back-on-without-the-forge ()
  (revu-test--with-set-base
    (revu-test--with-stubs
        ((revu--pr-ctx (lambda (&optional _) (error "the forge must not be asked"))))
      (revu-diff-hl-set-base "/tmp/wt/" "master")
      (revu-diff-hl-toggle)
      (revu-diff-hl-toggle)
      (should (equal revu-test--pointed-at "cafe1234"))
      (should revu-diff-hl-line-mode))))

(ert-deftest revu-test-diff-hl-toggle-asks-the-forge-when-unknown ()
  (revu-test--with-set-base
    (revu-test--with-stubs
        ((revu--pr-ctx (lambda (&optional _) '((base . "trunk")))))
      (revu-diff-hl-toggle)
      (should (equal (revu-diff-hl--base-ref "/tmp/wt/") "trunk"))
      (should revu-diff-hl-line-mode))))

(ert-deftest revu-test-diff-hl-toggle-sees-a-reference-set-by-hand ()
  (revu-test--with-set-base
    (let ((diff-hl-reference-revision "deadbeef"))
      (should (revu-diff-hl--active-p "/tmp/wt/")))))

;;;; Entry points

(ert-deftest revu-test-entry-points-are-commands ()
  (dolist (cmd '(revu-comment revu-list revu-submit
                 revu-refresh revu-cancel))
    (should (commandp cmd))))

(ert-deftest revu-test-prefix-map-is-bound ()
  (should (eq (lookup-key revu-prefix-map "c") #'revu-comment))
  (should (eq (lookup-key revu-prefix-map "l") #'revu-list))
  (should (eq (lookup-key revu-prefix-map "s") #'revu-submit))
  (should (eq (lookup-key revu-prefix-map "f") #'revu-refresh))
  (should (eq (lookup-key revu-prefix-map "h") #'revu-diff-hl-toggle)))

;;;; Default bindings

(defun revu-test--call-with-prefix (prefix thunk)
  "Set `revu-keymap-prefix' to PREFIX around THUNK, restoring it after."
  (let ((saved revu-keymap-prefix))
    (unwind-protect
        (progn (customize-set-variable 'revu-keymap-prefix prefix)
               (funcall thunk))
      (customize-set-variable 'revu-keymap-prefix saved))))

(ert-deftest revu-test-default-prefix-reaches-the-commands ()
  (should (eq (keymap-lookup revu-mode-map "C-c v c") #'revu-comment)))

(ert-deftest revu-test-changing-the-prefix-moves-the-binding ()
  (revu-test--call-with-prefix
   "C-c R"
   (lambda ()
     (should (eq (keymap-lookup revu-mode-map "C-c R c") #'revu-comment))
     ;; the old prefix is gone rather than left behind alongside the new one.
     ;; Look the prefix itself up: a lookup of the full sequence answers with
     ;; the length of the part that matched, which is not nil.
     (should-not (keymap-lookup revu-mode-map "C-c v")))))

(ert-deftest revu-test-nil-prefix-binds-nothing ()
  (revu-test--call-with-prefix
   nil
   (lambda ()
     (should-not (keymap-lookup revu-mode-map "C-c v")))))

(ert-deftest revu-test-mode-is-off-until-enabled ()
  (should-not revu-mode))

(provide 'revu-test)
;;; revu-test.el ends here
