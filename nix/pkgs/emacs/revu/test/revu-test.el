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

;;;; Entry points

(ert-deftest revu-test-entry-points-are-commands ()
  (dolist (cmd '(revu-comment revu-list revu-submit
                 revu-refresh revu-cancel))
    (should (commandp cmd))))

(ert-deftest revu-test-prefix-map-is-bound ()
  (should (eq (lookup-key revu-prefix-map "c") #'revu-comment))
  (should (eq (lookup-key revu-prefix-map "l") #'revu-list))
  (should (eq (lookup-key revu-prefix-map "s") #'revu-submit))
  (should (eq (lookup-key revu-prefix-map "f") #'revu-refresh)))

(provide 'revu-test)
;;; revu-test.el ends here
