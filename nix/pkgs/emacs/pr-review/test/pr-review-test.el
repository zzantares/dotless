;;; pr-review-test.el --- Tests for pr-review -*- lexical-binding: t; -*-

;;; Commentary:

;; Hermetic ERT suite: no network, no `gh', no magit, no forge.  Stubs stand in
;; for the process boundary and record what would have been sent, so the tests
;; assert on the GraphQL query and variables rather than on a live PR.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'pr-review)

;;;; Stub helper

(defun pr-review-test--call-with-stubs (stubs thunk)
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

(defmacro pr-review-test--with-stubs (bindings &rest body)
  "Evaluate BODY with BINDINGS, a list of (SYMBOL FUNCTION), installed."
  (declare (indent 1) (debug ((&rest (symbolp form)) body)))
  `(pr-review-test--call-with-stubs
    (list ,@(mapcar (lambda (b) `(cons ',(car b) ,(cadr b))) bindings))
    (lambda () ,@body)))

(defvar pr-review-test--payload nil
  "Stdin handed to the last stubbed `call-process-region'.")

(defun pr-review-test--stdin-stub (exit json)
  "Return a `call-process-region' stub answering JSON and exiting with EXIT."
  (lambda (beg end _program &optional _delete buffer &rest _args)
    (setq pr-review-test--payload (buffer-substring-no-properties beg end))
    (when (bufferp buffer)
      (with-current-buffer buffer (insert json)))
    exit))

(defun pr-review-test--process-stub (exit json)
  "Return a `call-process' stub answering JSON and exiting with EXIT."
  (lambda (_program &optional _infile destination &rest _args)
    (when (bufferp destination)
      (with-current-buffer destination (insert json)))
    exit))

(defun pr-review-test--recorder (result)
  "Return a `pr-review--graphql' stub that records into a cons and returns RESULT."
  (let ((cell (cons nil nil)))
    (cons cell (lambda (query variables)
                 (setcar cell query)
                 (setcdr cell variables)
                 result))))

;;;; `gh' resolution

(ert-deftest pr-review-test-gh-absolute-path-must-be-executable ()
  "An absolute `pr-review-gh-executable' is used only when it is executable."
  (let ((exe (make-temp-file "pr-review-gh")))
    (unwind-protect
        (let ((pr-review-gh-executable exe))
          (set-file-modes exe #o755)
          (should (equal (pr-review--gh) exe))
          (set-file-modes exe #o644)
          (should-error (pr-review--gh) :type 'user-error))
      (delete-file exe))))

(ert-deftest pr-review-test-gh-relative-name-goes-through-path ()
  (pr-review-test--with-stubs
      ((executable-find (lambda (n &rest _) (and (equal n "gh") "/usr/bin/gh"))))
    (let ((pr-review-gh-executable "gh"))
      (should (equal (pr-review--gh) "/usr/bin/gh")))))

(ert-deftest pr-review-test-gh-missing-signals-user-error ()
  "A missing CLI is a user error, not a crash inside `call-process'."
  (pr-review-test--with-stubs
      ((executable-find (lambda (&rest _) nil)))
    (let ((pr-review-gh-executable "not-on-path"))
      (should-error (pr-review--gh) :type 'user-error))))

;;;; GraphQL transport

(ert-deftest pr-review-test-graphql-returns-the-data-alist ()
  (pr-review-test--with-stubs
      ((pr-review--gh (lambda () "/bin/true"))
       (call-process-region
        (pr-review-test--stdin-stub 0 "{\"data\":{\"node\":{\"id\":\"R_1\"}}}")))
    (let ((data (pr-review--graphql "query{}" nil)))
      (should (equal (alist-get 'id (alist-get 'node data)) "R_1")))))

(ert-deftest pr-review-test-graphql-sends-query-and-variables-on-stdin ()
  (setq pr-review-test--payload nil)
  (pr-review-test--with-stubs
      ((pr-review--gh (lambda () "/bin/true"))
       (call-process-region (pr-review-test--stdin-stub 0 "{\"data\":{}}")))
    (pr-review--graphql "query($x:ID!){ node(id:$x){ id } }" '((x . "PR_1"))))
  (let ((sent (json-parse-string pr-review-test--payload :object-type 'alist)))
    (should (equal (alist-get 'query sent) "query($x:ID!){ node(id:$x){ id } }"))
    (should (equal (alist-get 'x (alist-get 'variables sent)) "PR_1"))))

(ert-deftest pr-review-test-graphql-reports-the-forge-error-message ()
  "A GraphQL `errors' array must surface its message, not the raw buffer."
  (pr-review-test--with-stubs
      ((pr-review--gh (lambda () "/bin/true"))
       (call-process-region
        (pr-review-test--stdin-stub
         1 "{\"errors\":[{\"message\":\"Could not resolve to a node\"}]}")))
    (let ((err (should-error (pr-review--graphql "q" nil))))
      (should (string-match-p "Could not resolve to a node"
                              (error-message-string err))))))

(ert-deftest pr-review-test-graphql-signals-on-unparseable-output ()
  (pr-review-test--with-stubs
      ((pr-review--gh (lambda () "/bin/true"))
       (call-process-region (pr-review-test--stdin-stub 1 "gh: command failed")))
    (should-error (pr-review--graphql "q" nil))))

(ert-deftest pr-review-test-graphql-does-not-leak-its-buffer ()
  "The work buffer is killed on the success and the failure path alike."
  (pr-review-test--with-stubs
      ((pr-review--gh (lambda () "/bin/true"))
       (call-process-region (pr-review-test--stdin-stub 0 "{\"data\":{}}")))
    (pr-review--graphql "q" nil))
  (should-not (get-buffer " *pr-review-graphql*"))
  (pr-review-test--with-stubs
      ((pr-review--gh (lambda () "/bin/true"))
       (call-process-region (pr-review-test--stdin-stub 1 "boom")))
    (ignore-errors (pr-review--graphql "q" nil)))
  (should-not (get-buffer " *pr-review-graphql*")))

;;;; PR context

(ert-deftest pr-review-test-pr-ctx-parses-gh-json ()
  (pr-review-test--with-stubs
      ((pr-review--gh (lambda () "/bin/true"))
       (call-process
        (pr-review-test--process-stub
         0 (concat "{\"id\":\"PR_1\",\"number\":97,"
                   "\"baseRefName\":\"master\",\"headRefOid\":\"abc123\"}"))))
    (let ((ctx (pr-review--pr-ctx "/tmp")))
      (should (equal (alist-get 'id ctx) "PR_1"))
      (should (equal (alist-get 'number ctx) 97))
      (should (equal (alist-get 'base ctx) "master"))
      (should (equal (alist-get 'head ctx) "abc123")))))

(ert-deftest pr-review-test-pr-ctx-errors-without-an-open-pr ()
  (pr-review-test--with-stubs
      ((pr-review--gh (lambda () "/bin/true"))
       (call-process (pr-review-test--process-stub 1 "no pull requests found")))
    (should-error (pr-review--pr-ctx "/tmp"))))

(ert-deftest pr-review-test-pr-ctx-does-not-leak-its-buffer ()
  (pr-review-test--with-stubs
      ((pr-review--gh (lambda () "/bin/true"))
       (call-process (pr-review-test--process-stub 1 "nope")))
    (ignore-errors (pr-review--pr-ctx "/tmp")))
  (should-not (get-buffer " *pr-review-pr-view*")))

;;;; Pending review discovery

(ert-deftest pr-review-test-pending-review-returns-the-first-node ()
  (pr-review-test--with-stubs
      ((pr-review--graphql
        (lambda (&rest _)
          '((node . ((reviews . ((nodes . (((id . "PRR_1")) ((id . "PRR_2"))))))))))))
    (should (equal (pr-review--pending-review "PR_1") "PRR_1"))))

(ert-deftest pr-review-test-pending-review-nil-when-none ()
  (pr-review-test--with-stubs
      ((pr-review--graphql (lambda (&rest _) '((node . ((reviews . ((nodes . nil))))))))) 
    (should-not (pr-review--pending-review "PR_1"))))

(ert-deftest pr-review-test-ensure-review-reuses-a-pending-review ()
  "Reusing must not issue a mutation: GitHub allows only one pending review."
  (let ((mutations 0))
    (pr-review-test--with-stubs
        ((pr-review--pending-review (lambda (_) "PRR_existing"))
         (pr-review--graphql (lambda (&rest _) (cl-incf mutations) nil)))
      (should (equal (pr-review--ensure-review "PR_1" "sha") "PRR_existing"))
      (should (= mutations 0)))))

(ert-deftest pr-review-test-ensure-review-creates-one-pinned-to-head ()
  (let* ((rec (pr-review-test--recorder
               '((addPullRequestReview . ((pullRequestReview . ((id . "PRR_new"))))))))
         (cell (car rec)))
    (pr-review-test--with-stubs
        ((pr-review--pending-review (lambda (_) nil))
         (pr-review--graphql (cdr rec)))
      (should (equal (pr-review--ensure-review "PR_1" "deadbeef") "PRR_new"))
      (should (string-match-p "addPullRequestReview" (car cell)))
      (should (equal (alist-get 'oid (cdr cell)) "deadbeef")))))

;;;; Draft threads

(ert-deftest pr-review-test-add-thread-single-line-omits-start-line ()
  (let* ((rec (pr-review-test--recorder nil))
         (cell (car rec)))
    (pr-review-test--with-stubs ((pr-review--graphql (cdr rec)))
      (pr-review--add-thread "PRR_1" "a/b.el" 42 nil "hi")
      (should-not (string-match-p "startLine" (car cell)))
      (should (equal (alist-get 'l (cdr cell)) 42))
      (should-not (assq 's (cdr cell))))))

(ert-deftest pr-review-test-add-thread-range-sends-start-line ()
  (let* ((rec (pr-review-test--recorder nil))
         (cell (car rec)))
    (pr-review-test--with-stubs ((pr-review--graphql (cdr rec)))
      (pr-review--add-thread "PRR_1" "a/b.el" 42 40 "hi")
      (should (string-match-p "startLine:\\$s" (car cell)))
      (should (equal (alist-get 's (cdr cell)) 40))
      (should (equal (alist-get 'l (cdr cell)) 42)))))

(ert-deftest pr-review-test-add-thread-collapses-a-degenerate-range ()
  "A one-line region is a single-line comment, not a 42..42 range."
  (let* ((rec (pr-review-test--recorder nil))
         (cell (car rec)))
    (pr-review-test--with-stubs ((pr-review--graphql (cdr rec)))
      (pr-review--add-thread "PRR_1" "a/b.el" 42 42 "hi")
      (should-not (string-match-p "startLine" (car cell)))
      (should-not (assq 's (cdr cell))))))

;;;; Comment composer

(defun pr-review-test--in-file-buffer (fn)
  "Call FN with (DIR FILE) inside a buffer visiting a file under a temp DIR."
  (let* ((dir (make-temp-file "pr-review-repo" t))
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

(ert-deftest pr-review-test-comment-targets-the-current-line ()
  (pr-review-test--in-file-buffer
   (lambda (dir _file)
     (pr-review-test--with-stubs
         ((pr-review--gh (lambda () "/bin/true"))
          (magit-toplevel (lambda (&rest _) dir))
          (magit-file-relative-name (lambda (&rest _) "src/thing.el"))
          (pop-to-buffer (lambda (&rest _) nil)))
       (goto-char (point-min))
       (forward-line 1)
       (pr-review-comment (line-beginning-position) (line-end-position))
       (with-current-buffer "*pr-review-comment*"
         (should (equal (alist-get 'path pr-review--comment-ctx) "src/thing.el"))
         (should (equal (alist-get 'line pr-review--comment-ctx) 2))
         (should-not (alist-get 'start-line pr-review--comment-ctx)))))))

(ert-deftest pr-review-test-comment-region-ending-at-bol-drops-the-last-line ()
  "Selecting lines 1-2 leaves point at the start of line 3; that is not line 3."
  (pr-review-test--in-file-buffer
   (lambda (dir _file)
     (pr-review-test--with-stubs
         ((pr-review--gh (lambda () "/bin/true"))
          (magit-toplevel (lambda (&rest _) dir))
          (magit-file-relative-name (lambda (&rest _) "src/thing.el"))
          (pop-to-buffer (lambda (&rest _) nil)))
       (let ((beg (point-min))
             (end (save-excursion (goto-char (point-min)) (forward-line 2) (point))))
         (pr-review-comment beg end))
       (with-current-buffer "*pr-review-comment*"
         (should (equal (alist-get 'start-line pr-review--comment-ctx) 1))
         (should (equal (alist-get 'line pr-review--comment-ctx) 2)))))))

(ert-deftest pr-review-test-comment-refuses-an-unsaved-buffer ()
  "Line numbers are meaningless against the PR head if the buffer is dirty."
  (pr-review-test--in-file-buffer
   (lambda (dir _file)
     (pr-review-test--with-stubs
         ((pr-review--gh (lambda () "/bin/true"))
          (magit-toplevel (lambda (&rest _) dir))
          (magit-file-relative-name (lambda (&rest _) "src/thing.el")))
       (goto-char (point-max))
       (insert "dirty\n")
       (should-error (pr-review-comment (point-min) (point-max)) :type 'user-error)))))

(ert-deftest pr-review-test-comment-refuses-a-non-file-buffer ()
  (pr-review-test--with-stubs ((pr-review--gh (lambda () "/bin/true")))
    (with-temp-buffer
      (should-error (pr-review-comment (point-min) (point-max)) :type 'user-error))))

;;;; Submit

(ert-deftest pr-review-test-submit-maps-events-to-the-graphql-enum ()
  (dolist (case '((approve . "APPROVE")
                  (request-changes . "REQUEST_CHANGES")
                  (comment . "COMMENT")
                  (nil . "COMMENT")))
    (pr-review-test--with-stubs
        ((magit-toplevel (lambda (&rest _) "/tmp"))
         (pr-review--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 97))))
         (pr-review--pending-review (lambda (_) "PRR_1"))
         (pop-to-buffer (lambda (&rest _) nil)))
      (pr-review-submit (car case))
      (with-current-buffer "*pr-review-submit*"
        (should (equal (alist-get 'event pr-review--submit-ctx) (cdr case)))))))

(ert-deftest pr-review-test-submit-errors-without-a-pending-review ()
  (pr-review-test--with-stubs
      ((magit-toplevel (lambda (&rest _) "/tmp"))
       (pr-review--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 97))))
       (pr-review--pending-review (lambda (_) nil)))
    (should-error (pr-review-submit 'approve) :type 'user-error)))

(ert-deftest pr-review-test-submit-send-omits-an-empty-body ()
  "GitHub rejects an empty body string; the variable must be absent instead."
  (let* ((rec (pr-review-test--recorder
               '((submitPullRequestReview
                  . ((pullRequestReview . ((url . "https://example/1")
                                           (state . "APPROVED"))))))))
         (cell (car rec)))
    (pr-review-test--with-stubs
        ((pr-review--graphql (cdr rec))
         (quit-window (lambda (&rest _) nil)))
      (with-temp-buffer
        (setq pr-review--submit-ctx
              '((root . "/tmp") (review . "PRR_1") (event . "APPROVE") (number . 97)))
        (insert "   \n  ")
        (pr-review--submit-send))
      (should (equal (alist-get 'e (cdr cell)) "APPROVE"))
      (should (equal (alist-get 'r (cdr cell)) "PRR_1"))
      (should-not (assq 'b (cdr cell))))))

(ert-deftest pr-review-test-submit-send-passes-a-trimmed-body ()
  (let* ((rec (pr-review-test--recorder
               '((submitPullRequestReview
                  . ((pullRequestReview . ((url . "https://example/1")
                                           (state . "COMMENTED"))))))))
         (cell (car rec)))
    (pr-review-test--with-stubs
        ((pr-review--graphql (cdr rec))
         (quit-window (lambda (&rest _) nil)))
      (with-temp-buffer
        (setq pr-review--submit-ctx
              '((root . "/tmp") (review . "PRR_1") (event . "COMMENT") (number . 97)))
        (insert "\n  looks good  \n")
        (pr-review--submit-send))
      (should (equal (alist-get 'b (cdr cell)) "looks good")))))

;;;; Forge integration

(ert-deftest pr-review-test-forge-mode-adds-and-removes-its-advice ()
  (pr-review-test--with-stubs
      ((forge-approve-pullreq (lambda (&rest _) 'native))
       (forge-request-changes (lambda (&rest _) 'native)))
    (unwind-protect
        (progn
          (pr-review-forge-mode 1)
          (should (advice-member-p #'pr-review--forge-approve-advice
                                   'forge-approve-pullreq))
          (should (advice-member-p #'pr-review--forge-request-changes-advice
                                   'forge-request-changes))
          (pr-review-forge-mode -1)
          (should-not (advice-member-p #'pr-review--forge-approve-advice
                                       'forge-approve-pullreq))
          (should-not (advice-member-p #'pr-review--forge-request-changes-advice
                                       'forge-request-changes)))
      (pr-review-forge-mode -1))))

(ert-deftest pr-review-test-forge-falls-back-to-native-without-drafts ()
  "With no pending review, Forge's own body-only review must still work."
  (let (called)
    (pr-review-test--with-stubs
        ((magit-toplevel (lambda (&rest _) "/tmp"))
         (pr-review--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 1))))
         (pr-review--pending-review (lambda (_) nil))
         (pr-review-submit (lambda (&rest _) (setq called 'batched))))
      (pr-review--maybe-submit-via-forge
       'approve (lambda (&rest _) (setq called 'native)) nil)
      (should (eq called 'native)))))

(ert-deftest pr-review-test-forge-routes-to-the-batch-submitter-with-drafts ()
  (let (called)
    (pr-review-test--with-stubs
        ((magit-toplevel (lambda (&rest _) "/tmp"))
         (pr-review--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 1))))
         (pr-review--pending-review (lambda (_) "PRR_1"))
         (pr-review-submit (lambda (&rest _) (setq called 'batched))))
      (pr-review--maybe-submit-via-forge
       'approve (lambda (&rest _) (setq called 'native)) nil)
      (should (eq called 'batched)))))

(ert-deftest pr-review-test-forge-falls-back-outside-a-repository ()
  (let (called)
    (pr-review-test--with-stubs
        ((magit-toplevel (lambda (&rest _) nil))
         (pr-review-submit (lambda (&rest _) (setq called 'batched))))
      (pr-review--maybe-submit-via-forge
       'approve (lambda (&rest _) (setq called 'native)) nil)
      (should (eq called 'native)))))

;;;; Entry points

(ert-deftest pr-review-test-entry-points-are-commands ()
  (dolist (cmd '(pr-review-comment pr-review-list pr-review-submit
                 pr-review-refresh pr-review-cancel))
    (should (commandp cmd))))

(ert-deftest pr-review-test-prefix-map-is-bound ()
  (should (eq (lookup-key pr-review-prefix-map "c") #'pr-review-comment))
  (should (eq (lookup-key pr-review-prefix-map "l") #'pr-review-list))
  (should (eq (lookup-key pr-review-prefix-map "s") #'pr-review-submit))
  (should (eq (lookup-key pr-review-prefix-map "f") #'pr-review-refresh)))

(provide 'pr-review-test)
;;; pr-review-test.el ends here
