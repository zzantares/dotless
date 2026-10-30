;;; nitpick-test.el --- Tests for nitpick -*- lexical-binding: t; -*-

;;; Commentary:

;; Hermetic ERT suite: no network, no `gh', no magit, no forge.  Stubs stand in
;; for the process boundary and record what would have been sent, so the tests
;; assert on the GraphQL query and variables rather than on a live PR.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'nitpick)

;;;; Stub helper

(defun nitpick-test--call-with-stubs (stubs thunk)
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

(defmacro nitpick-test--with-stubs (bindings &rest body)
  "Evaluate BODY with BINDINGS, a list of (SYMBOL FUNCTION), installed."
  (declare (indent 1) (debug ((&rest (symbolp form)) body)))
  `(nitpick-test--call-with-stubs
    (list ,@(mapcar (lambda (b) `(cons ',(car b) ,(cadr b))) bindings))
    (lambda () ,@body)))

(defvar nitpick-test--payload nil
  "Stdin handed to the last stubbed `call-process-region'.")

(defun nitpick-test--stdin-stub (exit json)
  "Return a `call-process-region' stub answering JSON and exiting with EXIT."
  (lambda (beg end _program &optional _delete buffer &rest _args)
    (setq nitpick-test--payload (buffer-substring-no-properties beg end))
    (when (bufferp buffer)
      (with-current-buffer buffer (insert json)))
    exit))

(defun nitpick-test--process-stub (exit json)
  "Return a `call-process' stub answering JSON and exiting with EXIT."
  (lambda (_program &optional _infile destination &rest _args)
    (when (bufferp destination)
      (with-current-buffer destination (insert json)))
    exit))

(defun nitpick-test--recorder (result)
  "Return a `nitpick--graphql' stub that records into a cons and returns RESULT."
  (let ((cell (cons nil nil)))
    (cons cell (lambda (query variables)
                 (setcar cell query)
                 (setcdr cell variables)
                 result))))

;;;; `gh' resolution

(ert-deftest nitpick-test-gh-absolute-path-must-be-executable ()
  "An absolute `nitpick-gh-executable' is used only when it is executable."
  (let ((exe (make-temp-file "nitpick-gh")))
    (unwind-protect
        (let ((nitpick-gh-executable exe))
          (set-file-modes exe #o755)
          (should (equal (nitpick--gh) exe))
          (set-file-modes exe #o644)
          (should-error (nitpick--gh) :type 'user-error))
      (delete-file exe))))

(ert-deftest nitpick-test-gh-relative-name-goes-through-path ()
  (nitpick-test--with-stubs
      ((executable-find (lambda (n &rest _) (and (equal n "gh") "/usr/bin/gh"))))
    (let ((nitpick-gh-executable "gh"))
      (should (equal (nitpick--gh) "/usr/bin/gh")))))

(ert-deftest nitpick-test-gh-missing-signals-user-error ()
  "A missing CLI is a user error, not a crash inside `call-process'."
  (nitpick-test--with-stubs
      ((executable-find (lambda (&rest _) nil)))
    (let ((nitpick-gh-executable "not-on-path"))
      (should-error (nitpick--gh) :type 'user-error))))

;;;; GraphQL transport

(ert-deftest nitpick-test-graphql-returns-the-data-alist ()
  (nitpick-test--with-stubs
      ((nitpick--gh (lambda () "/bin/true"))
       (call-process-region
        (nitpick-test--stdin-stub 0 "{\"data\":{\"node\":{\"id\":\"R_1\"}}}")))
    (let ((data (nitpick--graphql "query{}" nil)))
      (should (equal (alist-get 'id (alist-get 'node data)) "R_1")))))

(ert-deftest nitpick-test-graphql-sends-query-and-variables-on-stdin ()
  (setq nitpick-test--payload nil)
  (nitpick-test--with-stubs
      ((nitpick--gh (lambda () "/bin/true"))
       (call-process-region (nitpick-test--stdin-stub 0 "{\"data\":{}}")))
    (nitpick--graphql "query($x:ID!){ node(id:$x){ id } }" '((x . "PR_1"))))
  (let ((sent (json-parse-string nitpick-test--payload :object-type 'alist)))
    (should (equal (alist-get 'query sent) "query($x:ID!){ node(id:$x){ id } }"))
    (should (equal (alist-get 'x (alist-get 'variables sent)) "PR_1"))))

(ert-deftest nitpick-test-graphql-reports-the-forge-error-message ()
  "A GraphQL `errors' array must surface its message, not the raw buffer."
  (nitpick-test--with-stubs
      ((nitpick--gh (lambda () "/bin/true"))
       (call-process-region
        (nitpick-test--stdin-stub
         1 "{\"errors\":[{\"message\":\"Could not resolve to a node\"}]}")))
    (let ((err (should-error (nitpick--graphql "q" nil))))
      (should (string-match-p "Could not resolve to a node"
                              (error-message-string err))))))

(ert-deftest nitpick-test-graphql-signals-on-unparseable-output ()
  (nitpick-test--with-stubs
      ((nitpick--gh (lambda () "/bin/true"))
       (call-process-region (nitpick-test--stdin-stub 1 "gh: command failed")))
    (should-error (nitpick--graphql "q" nil))))

(ert-deftest nitpick-test-graphql-does-not-leak-its-buffer ()
  "The work buffer is killed on the success and the failure path alike."
  (nitpick-test--with-stubs
      ((nitpick--gh (lambda () "/bin/true"))
       (call-process-region (nitpick-test--stdin-stub 0 "{\"data\":{}}")))
    (nitpick--graphql "q" nil))
  (should-not (get-buffer " *nitpick-graphql*"))
  (nitpick-test--with-stubs
      ((nitpick--gh (lambda () "/bin/true"))
       (call-process-region (nitpick-test--stdin-stub 1 "boom")))
    (ignore-errors (nitpick--graphql "q" nil)))
  (should-not (get-buffer " *nitpick-graphql*")))

;;;; PR context

(ert-deftest nitpick-test-pr-ctx-parses-gh-json ()
  (nitpick-test--with-stubs
      ((nitpick--gh (lambda () "/bin/true"))
       (call-process
        (nitpick-test--process-stub
         0 (concat "{\"id\":\"PR_1\",\"number\":97,"
                   "\"baseRefName\":\"master\",\"headRefOid\":\"abc123\"}"))))
    (let ((ctx (nitpick--pr-ctx "/tmp")))
      (should (equal (alist-get 'id ctx) "PR_1"))
      (should (equal (alist-get 'number ctx) 97))
      (should (equal (alist-get 'base ctx) "master"))
      (should (equal (alist-get 'head ctx) "abc123")))))

(ert-deftest nitpick-test-pr-ctx-errors-without-an-open-pr ()
  (nitpick-test--with-stubs
      ((nitpick--gh (lambda () "/bin/true"))
       (call-process (nitpick-test--process-stub 1 "no pull requests found")))
    (should-error (nitpick--pr-ctx "/tmp"))))

(ert-deftest nitpick-test-pr-ctx-does-not-leak-its-buffer ()
  (nitpick-test--with-stubs
      ((nitpick--gh (lambda () "/bin/true"))
       (call-process (nitpick-test--process-stub 1 "nope")))
    (ignore-errors (nitpick--pr-ctx "/tmp")))
  (should-not (get-buffer " *nitpick-pr-view*")))

;;;; Pending review discovery

(ert-deftest nitpick-test-pending-review-returns-the-first-node ()
  (nitpick-test--with-stubs
      ((nitpick--graphql
        (lambda (&rest _)
          '((node . ((reviews . ((nodes . (((id . "PRR_1")) ((id . "PRR_2"))))))))))))
    (should (equal (nitpick--pending-review "PR_1") "PRR_1"))))

(ert-deftest nitpick-test-pending-review-nil-when-none ()
  (nitpick-test--with-stubs
      ((nitpick--graphql (lambda (&rest _) '((node . ((reviews . ((nodes . nil))))))))) 
    (should-not (nitpick--pending-review "PR_1"))))

(ert-deftest nitpick-test-ensure-review-reuses-a-pending-review ()
  "Reusing must not issue a mutation: GitHub allows only one pending review."
  (let ((mutations 0))
    (nitpick-test--with-stubs
        ((nitpick--pending-review (lambda (_) "PRR_existing"))
         (nitpick--graphql (lambda (&rest _) (cl-incf mutations) nil)))
      (should (equal (nitpick--ensure-review "PR_1" "sha") "PRR_existing"))
      (should (= mutations 0)))))

(ert-deftest nitpick-test-ensure-review-creates-one-pinned-to-head ()
  (let* ((rec (nitpick-test--recorder
               '((addPullRequestReview . ((pullRequestReview . ((id . "PRR_new"))))))))
         (cell (car rec)))
    (nitpick-test--with-stubs
        ((nitpick--pending-review (lambda (_) nil))
         (nitpick--graphql (cdr rec)))
      (should (equal (nitpick--ensure-review "PR_1" "deadbeef") "PRR_new"))
      (should (string-match-p "addPullRequestReview" (car cell)))
      (should (equal (alist-get 'oid (cdr cell)) "deadbeef")))))

;;;; Draft threads

(ert-deftest nitpick-test-add-thread-single-line-omits-start-line ()
  (let* ((rec (nitpick-test--recorder nil))
         (cell (car rec)))
    (nitpick-test--with-stubs ((nitpick--graphql (cdr rec)))
      (nitpick--add-thread "PRR_1" "a/b.el" 42 nil "hi")
      (should-not (string-match-p "startLine" (car cell)))
      (should (equal (alist-get 'l (cdr cell)) 42))
      (should-not (assq 's (cdr cell))))))

(ert-deftest nitpick-test-add-thread-range-sends-start-line ()
  (let* ((rec (nitpick-test--recorder nil))
         (cell (car rec)))
    (nitpick-test--with-stubs ((nitpick--graphql (cdr rec)))
      (nitpick--add-thread "PRR_1" "a/b.el" 42 40 "hi")
      (should (string-match-p "startLine:\\$s" (car cell)))
      (should (equal (alist-get 's (cdr cell)) 40))
      (should (equal (alist-get 'l (cdr cell)) 42)))))

(ert-deftest nitpick-test-add-thread-collapses-a-degenerate-range ()
  "A one-line region is a single-line comment, not a 42..42 range."
  (let* ((rec (nitpick-test--recorder nil))
         (cell (car rec)))
    (nitpick-test--with-stubs ((nitpick--graphql (cdr rec)))
      (nitpick--add-thread "PRR_1" "a/b.el" 42 42 "hi")
      (should-not (string-match-p "startLine" (car cell)))
      (should-not (assq 's (cdr cell))))))

;;;; Comment composer

(defun nitpick-test--in-file-buffer (fn)
  "Call FN with (DIR FILE) inside a buffer visiting a file under a temp DIR."
  (let* ((dir (make-temp-file "nitpick-repo" t))
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

(ert-deftest nitpick-test-comment-targets-the-current-line ()
  (nitpick-test--in-file-buffer
   (lambda (dir _file)
     (nitpick-test--with-stubs
         ((nitpick--gh (lambda () "/bin/true"))
          (magit-toplevel (lambda (&rest _) dir))
          (magit-file-relative-name (lambda (&rest _) "src/thing.el"))
          (pop-to-buffer (lambda (&rest _) nil)))
       (goto-char (point-min))
       (forward-line 1)
       (nitpick-comment (line-beginning-position) (line-end-position))
       (with-current-buffer "*nitpick-comment*"
         (should (equal (alist-get 'path nitpick--comment-ctx) "src/thing.el"))
         (should (equal (alist-get 'line nitpick--comment-ctx) 2))
         (should-not (alist-get 'start-line nitpick--comment-ctx)))))))

(ert-deftest nitpick-test-comment-region-ending-at-bol-drops-the-last-line ()
  "Selecting lines 1-2 leaves point at the start of line 3; that is not line 3."
  (nitpick-test--in-file-buffer
   (lambda (dir _file)
     (nitpick-test--with-stubs
         ((nitpick--gh (lambda () "/bin/true"))
          (magit-toplevel (lambda (&rest _) dir))
          (magit-file-relative-name (lambda (&rest _) "src/thing.el"))
          (pop-to-buffer (lambda (&rest _) nil)))
       (let ((beg (point-min))
             (end (save-excursion (goto-char (point-min)) (forward-line 2) (point))))
         (nitpick-comment beg end))
       (with-current-buffer "*nitpick-comment*"
         (should (equal (alist-get 'start-line nitpick--comment-ctx) 1))
         (should (equal (alist-get 'line nitpick--comment-ctx) 2)))))))

(ert-deftest nitpick-test-comment-refuses-an-unsaved-buffer ()
  "Line numbers are meaningless against the PR head if the buffer is dirty."
  (nitpick-test--in-file-buffer
   (lambda (dir _file)
     (nitpick-test--with-stubs
         ((nitpick--gh (lambda () "/bin/true"))
          (magit-toplevel (lambda (&rest _) dir))
          (magit-file-relative-name (lambda (&rest _) "src/thing.el")))
       (goto-char (point-max))
       (insert "dirty\n")
       (should-error (nitpick-comment (point-min) (point-max)) :type 'user-error)))))

(ert-deftest nitpick-test-comment-refuses-a-non-file-buffer ()
  (nitpick-test--with-stubs ((nitpick--gh (lambda () "/bin/true")))
    (with-temp-buffer
      (should-error (nitpick-comment (point-min) (point-max)) :type 'user-error))))

;;;; Submit

(ert-deftest nitpick-test-submit-maps-events-to-the-graphql-enum ()
  (dolist (case '((approve . "APPROVE")
                  (request-changes . "REQUEST_CHANGES")
                  (comment . "COMMENT")
                  (nil . "COMMENT")))
    (nitpick-test--with-stubs
        ((magit-toplevel (lambda (&rest _) "/tmp"))
         (nitpick--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 97))))
         (nitpick--pending-review (lambda (_) "PRR_1"))
         (pop-to-buffer (lambda (&rest _) nil)))
      (nitpick-submit (car case))
      (with-current-buffer "*nitpick-submit*"
        (should (equal (alist-get 'event nitpick--submit-ctx) (cdr case)))))))

(ert-deftest nitpick-test-submit-errors-without-a-pending-review ()
  (nitpick-test--with-stubs
      ((magit-toplevel (lambda (&rest _) "/tmp"))
       (nitpick--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 97))))
       (nitpick--pending-review (lambda (_) nil)))
    (should-error (nitpick-submit 'approve) :type 'user-error)))

(ert-deftest nitpick-test-submit-send-omits-an-empty-body ()
  "GitHub rejects an empty body string; the variable must be absent instead."
  (let* ((rec (nitpick-test--recorder
               '((submitPullRequestReview
                  . ((pullRequestReview . ((url . "https://example/1")
                                           (state . "APPROVED"))))))))
         (cell (car rec)))
    (nitpick-test--with-stubs
        ((nitpick--graphql (cdr rec))
         (quit-window (lambda (&rest _) nil)))
      (with-temp-buffer
        (setq nitpick--submit-ctx
              '((root . "/tmp") (review . "PRR_1") (event . "APPROVE") (number . 97)))
        (insert "   \n  ")
        (nitpick--submit-send))
      (should (equal (alist-get 'e (cdr cell)) "APPROVE"))
      (should (equal (alist-get 'r (cdr cell)) "PRR_1"))
      (should-not (assq 'b (cdr cell))))))

(ert-deftest nitpick-test-submit-send-passes-a-trimmed-body ()
  (let* ((rec (nitpick-test--recorder
               '((submitPullRequestReview
                  . ((pullRequestReview . ((url . "https://example/1")
                                           (state . "COMMENTED"))))))))
         (cell (car rec)))
    (nitpick-test--with-stubs
        ((nitpick--graphql (cdr rec))
         (quit-window (lambda (&rest _) nil)))
      (with-temp-buffer
        (setq nitpick--submit-ctx
              '((root . "/tmp") (review . "PRR_1") (event . "COMMENT") (number . 97)))
        (insert "\n  looks good  \n")
        (nitpick--submit-send))
      (should (equal (alist-get 'b (cdr cell)) "looks good")))))

;;;; Forge integration

(ert-deftest nitpick-test-forge-mode-adds-and-removes-its-advice ()
  (nitpick-test--with-stubs
      ((forge-approve-pullreq (lambda (&rest _) 'native))
       (forge-request-changes (lambda (&rest _) 'native)))
    (unwind-protect
        (progn
          (nitpick-forge-mode 1)
          (should (advice-member-p #'nitpick--forge-approve-advice
                                   'forge-approve-pullreq))
          (should (advice-member-p #'nitpick--forge-request-changes-advice
                                   'forge-request-changes))
          (nitpick-forge-mode -1)
          (should-not (advice-member-p #'nitpick--forge-approve-advice
                                       'forge-approve-pullreq))
          (should-not (advice-member-p #'nitpick--forge-request-changes-advice
                                       'forge-request-changes)))
      (nitpick-forge-mode -1))))

(ert-deftest nitpick-test-forge-falls-back-to-native-without-drafts ()
  "With no pending review, Forge's own body-only review must still work."
  (let (called)
    (nitpick-test--with-stubs
        ((magit-toplevel (lambda (&rest _) "/tmp"))
         (nitpick--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 1))))
         (nitpick--pending-review (lambda (_) nil))
         (nitpick-submit (lambda (&rest _) (setq called 'batched))))
      (nitpick--maybe-submit-via-forge
       'approve (lambda (&rest _) (setq called 'native)) nil)
      (should (eq called 'native)))))

(ert-deftest nitpick-test-forge-routes-to-the-batch-submitter-with-drafts ()
  (let (called)
    (nitpick-test--with-stubs
        ((magit-toplevel (lambda (&rest _) "/tmp"))
         (nitpick--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 1))))
         (nitpick--pending-review (lambda (_) "PRR_1"))
         (nitpick-submit (lambda (&rest _) (setq called 'batched))))
      (nitpick--maybe-submit-via-forge
       'approve (lambda (&rest _) (setq called 'native)) nil)
      (should (eq called 'batched)))))

(ert-deftest nitpick-test-forge-falls-back-outside-a-repository ()
  (let (called)
    (nitpick-test--with-stubs
        ((magit-toplevel (lambda (&rest _) nil))
         (nitpick-submit (lambda (&rest _) (setq called 'batched))))
      (nitpick--maybe-submit-via-forge
       'approve (lambda (&rest _) (setq called 'native)) nil)
      (should (eq called 'native)))))

;;;; diff-hl whole-line highlighting

;; diff-hl is not in scope at build time: nitpick.el only declares these two
;; variables special, so give them a dynamic binding to fake.
(defvar diff-hl-reference-revision nil)
(defvar diff-hl-highlight-function nil)
(defvar diff-hl-highlight-reference-function nil)

(defmacro nitpick-test--with-diff-hl (&rest body)
  "Run BODY with diff-hl's two highlight slots bound to recording stubs.
diff-hl is not in scope at build time, so the slots and the functions they
hold are faked; the suite asserts on the overlays nitpick produces."
  (declare (indent 0))
  `(let ((diff-hl-highlight-function 'nitpick-test--inner-working)
         (diff-hl-highlight-reference-function 'nitpick-test--inner-reference)
         (nitpick-diff-hl--saved nil)
         (nitpick-diff-hl--pointed nil)
         (nitpick-diff-hl-line-mode nil)
         (nitpick-test--inner-calls nil))
     (nitpick-test--with-stubs
         ((nitpick-test--inner-working
           (lambda (&rest args) (push (cons 'working args) nitpick-test--inner-calls)))
          (nitpick-test--inner-reference
           (lambda (&rest args) (push (cons 'reference args) nitpick-test--inner-calls)))
          (diff-hl-update (lambda () nil)))
       ,@body)))

(defvar nitpick-test--inner-calls nil
  "Calls recorded by the stubbed diff-hl highlight functions.")

(defun nitpick-test--line-overlay (line)
  "Return a zero-width overlay at the start of LINE, as diff-hl makes one."
  (goto-char (point-min))
  (forward-line (1- line))
  (make-overlay (point) (point)))

(defmacro nitpick-test--in-buffer (&rest body)
  "Run BODY in a three-line temp buffer."
  (declare (indent 0))
  `(with-temp-buffer
     (insert "alpha\nbeta\ngamma\n")
     ,@body))

(ert-deftest nitpick-test-diff-hl-paints-the-whole-line ()
  (nitpick-test--in-buffer
    (let ((ovl (nitpick-test--line-overlay 2)))
      (nitpick-diff-hl--paint-line ovl 'insert)
      ;; the span covers "beta" and its newline, so an `:extend' face reaches
      ;; the window edge
      (should (equal (buffer-substring-no-properties
                      (overlay-start ovl) (overlay-end ovl))
                     "beta\n"))
      (should (eq (overlay-get ovl 'face) 'nitpick-diff-hl-line-insert))
      (should (eq (overlay-get ovl 'priority) nitpick-diff-hl-line-priority)))))

(ert-deftest nitpick-test-diff-hl-paints-a-change-with-the-change-face ()
  (nitpick-test--in-buffer
    (let ((ovl (nitpick-test--line-overlay 1)))
      (nitpick-diff-hl--paint-line ovl 'change)
      (should (eq (overlay-get ovl 'face) 'nitpick-diff-hl-line-change)))))

(ert-deftest nitpick-test-diff-hl-leaves-deletions-to-the-fringe ()
  (nitpick-test--in-buffer
    (let ((ovl (nitpick-test--line-overlay 2)))
      ;; nothing was removed from the line the overlay sits on, so it must not
      ;; be painted, and must stay zero-width
      (nitpick-diff-hl--paint-line ovl 'delete)
      (should-not (overlay-get ovl 'face))
      (should (= (overlay-start ovl) (overlay-end ovl))))))

(ert-deftest nitpick-test-diff-hl-clears-a-recycled-overlay ()
  (nitpick-test--in-buffer
    (let ((ovl (nitpick-test--line-overlay 2)))
      (nitpick-diff-hl--paint-line ovl 'insert)
      (nitpick-diff-hl--paint-line ovl 'delete)
      (should-not (overlay-get ovl 'face)))))

(ert-deftest nitpick-test-diff-hl-last-line-without-a-newline ()
  (with-temp-buffer
    (insert "alpha\nomega")
    (let ((ovl (nitpick-test--line-overlay 2)))
      (nitpick-diff-hl--paint-line ovl 'insert)
      (should (= (overlay-end ovl) (point-max))))))

(ert-deftest nitpick-test-diff-hl-line-mode-swaps-both-slots ()
  (nitpick-test--with-diff-hl
    (nitpick-diff-hl-line-mode 1)
    (should (eq diff-hl-highlight-function #'nitpick-diff-hl-highlight-line))
    (should (eq diff-hl-highlight-reference-function
                #'nitpick-diff-hl-highlight-line-flat))))

(ert-deftest nitpick-test-diff-hl-line-mode-restores-both-slots ()
  (nitpick-test--with-diff-hl
    (nitpick-diff-hl-line-mode 1)
    (nitpick-diff-hl-line-mode 1)
    (nitpick-diff-hl-line-mode -1)
    (should (eq diff-hl-highlight-function 'nitpick-test--inner-working))
    (should (eq diff-hl-highlight-reference-function 'nitpick-test--inner-reference))
    (should-not nitpick-diff-hl--saved)))

(ert-deftest nitpick-test-diff-hl-line-mode-keeps-the-inner-highlighting ()
  (nitpick-test--with-diff-hl
    (nitpick-diff-hl-line-mode 1)
    (nitpick-test--in-buffer
      (let ((ovl (nitpick-test--line-overlay 2)))
        (funcall diff-hl-highlight-function ovl 'insert 'single)
        (funcall diff-hl-highlight-reference-function ovl 'insert 'single)
        (should (equal (mapcar #'car nitpick-test--inner-calls)
                       '(reference working)))
        (should (eq (overlay-get ovl 'face) 'nitpick-diff-hl-line-insert))))))

(defmacro nitpick-test--with-set-base (&rest body)
  "Run BODY with `nitpick-diff-hl-set-base' stubbed down to its own logic.
Magit, diff-hl and the project are faked; `nitpick-diff-hl--bases' starts empty."
  (declare (indent 0))
  `(nitpick-test--with-diff-hl
     (let ((nitpick-diff-hl--bases nil)
           (nitpick-test--pointed-at nil))
       (nitpick-test--with-stubs
           ((magit-toplevel (lambda (&optional _) "/tmp/wt/"))
            (magit-git-string (lambda (&rest _) "cafe1234"))
            (magit-rev-abbrev (lambda (_) "cafe123"))
            (project-current (lambda (&optional _ _) '(transient . "/tmp/wt/")))
            (diff-hl-set-reference-rev-in-project-internal
             (lambda (rev _proj) (setq nitpick-test--pointed-at rev)))
            (magit-rev-verify (lambda (_) nil)))
         ,@body))))

(defvar nitpick-test--pointed-at nil
  "Reference revision handed to the stubbed diff-hl.")

(defvar nitpick-test--merge-base-args nil
  "Arguments the stubbed `magit-git-string' last saw.")

(ert-deftest nitpick-test-diff-hl-set-base-leaves-the-line-mode-alone ()
  (nitpick-test--with-set-base
    (nitpick-diff-hl-line-mode -1)
    (nitpick-diff-hl-set-base "/tmp/wt/" "master")
    (should-not nitpick-diff-hl-line-mode)
    (nitpick-diff-hl-line-mode 1)
    (nitpick-diff-hl-set-base "/tmp/wt/" "master")
    (should nitpick-diff-hl-line-mode)
    (nitpick-diff-hl-line-mode -1)))

(ert-deftest nitpick-test-diff-hl-set-base-is-a-command ()
  (should (commandp 'nitpick-diff-hl-set-base)))

(ert-deftest nitpick-test-diff-hl-set-base-remembers-the-revision ()
  (nitpick-test--with-set-base
    (nitpick-diff-hl-set-base "/tmp/wt" "develop")
    ;; keyed by one spelling, so a root without the trailing slash still hits
    (should (equal (nitpick-diff-hl--suggested-base "/tmp/wt/") "develop"))))

(ert-deftest nitpick-test-diff-hl-set-base-takes-the-revision-as-given ()
  (nitpick-test--with-set-base
    (nitpick-test--with-stubs
        ((magit-git-string
          (lambda (&rest args) (setq nitpick-test--merge-base-args args) "cafe1234")))
      ;; no remote glued on: origin/master and master are different answers
      (nitpick-diff-hl-set-base "/tmp/wt/" "origin/master")
      (should (equal nitpick-test--merge-base-args '("merge-base" "origin/master" "HEAD")))
      (nitpick-diff-hl-set-base "/tmp/wt/" "master")
      (should (equal nitpick-test--merge-base-args '("merge-base" "master" "HEAD")))
      ;; and HEAD is just one of the revisions you can pick
      (nitpick-diff-hl-set-base "/tmp/wt/" "HEAD")
      (should (equal nitpick-test--merge-base-args '("merge-base" "HEAD" "HEAD"))))))

;;;; Entry points

(ert-deftest nitpick-test-entry-points-are-commands ()
  (dolist (cmd '(nitpick-comment nitpick-list nitpick-submit
                 nitpick-refresh nitpick-cancel))
    (should (commandp cmd))))

(ert-deftest nitpick-test-prefix-map-is-bound ()
  (should (eq (lookup-key nitpick-prefix-map "c") #'nitpick-comment))
  (should (eq (lookup-key nitpick-prefix-map "l") #'nitpick-list))
  (should (eq (lookup-key nitpick-prefix-map "s") #'nitpick-submit))
  (should (eq (lookup-key nitpick-prefix-map "f") #'nitpick-refresh))
  (should (eq (lookup-key nitpick-prefix-map "b") #'nitpick-diff-hl-set-base))
  (should (eq (lookup-key nitpick-prefix-map "H") #'nitpick-diff-hl-line-mode)))

;;;; Default bindings

(defun nitpick-test--call-with-prefix (prefix thunk)
  "Set `nitpick-keymap-prefix' to PREFIX around THUNK, restoring it after."
  (let ((saved nitpick-keymap-prefix))
    (unwind-protect
        (progn (customize-set-variable 'nitpick-keymap-prefix prefix)
               (funcall thunk))
      (customize-set-variable 'nitpick-keymap-prefix saved))))

(ert-deftest nitpick-test-default-prefix-reaches-the-commands ()
  (should (eq (keymap-lookup nitpick-mode-map "C-c v c") #'nitpick-comment)))

(ert-deftest nitpick-test-changing-the-prefix-moves-the-binding ()
  (nitpick-test--call-with-prefix
   "C-c R"
   (lambda ()
     (should (eq (keymap-lookup nitpick-mode-map "C-c R c") #'nitpick-comment))
     ;; the old prefix is gone rather than left behind alongside the new one.
     ;; Look the prefix itself up: a lookup of the full sequence answers with
     ;; the length of the part that matched, which is not nil.
     (should-not (keymap-lookup nitpick-mode-map "C-c v")))))

(ert-deftest nitpick-test-nil-prefix-binds-nothing ()
  (nitpick-test--call-with-prefix
   nil
   (lambda ()
     (should-not (keymap-lookup nitpick-mode-map "C-c v")))))

(ert-deftest nitpick-test-mode-is-off-until-enabled ()
  (should-not nitpick-mode))

;;;; diff-hl: what the prompt suggests

(ert-deftest nitpick-test-suggested-base-prefers-the-remembered-revision ()
  "A revision already picked for this worktree wins, as picked; no forge call."
  (let ((nitpick-diff-hl--bases (list (cons "/tmp/wt/" "release/2.4"))))
    (nitpick-test--with-stubs
        ((nitpick--pr-ctx (lambda (&rest _) (error "should not reach the forge"))))
      (should (equal (nitpick-diff-hl--suggested-base "/tmp/wt") "release/2.4")))))

(ert-deftest nitpick-test-suggested-base-uses-the-pr-base-when-there-is-one ()
  "A stacked or release-targeting PR gets its base from the forge, as the
remote has it - the forge diffs against the remote's copy, not a local branch."
  (let ((nitpick-diff-hl--bases nil))
    (nitpick-test--with-stubs
        ((nitpick--pr-ctx (lambda (&rest _) '((base . "feature/parent"))))
         (magit-main-branch (lambda () "master")))
      (should (equal (nitpick-diff-hl--suggested-base "/tmp/wt")
                     "origin/feature/parent")))))

(ert-deftest nitpick-test-suggested-base-falls-back-to-the-default-branch ()
  "No open PR is not an error: the repository's default branch answers."
  (let ((nitpick-diff-hl--bases nil))
    (nitpick-test--with-stubs
        ((nitpick--pr-ctx (lambda (&rest _) (error "gh pr view failed")))
         (magit-main-branch (lambda () "master"))
         (magit-git-string (lambda (&rest _) nil)))
      (should (equal (nitpick-diff-hl--suggested-base "/tmp/wt") "origin/master")))))

(ert-deftest nitpick-test-default-base-reads-the-remote-head ()
  "Without `magit-main-branch', the remote's HEAD answers, remote stripped."
  (nitpick-test--with-stubs
      ((forge--get-remote (lambda (&rest _) "upstream"))
       (magit-main-branch (lambda () nil))
       (magit-git-string (lambda (&rest args)
                           (and (equal (car args) "symbolic-ref")
                                "upstream/trunk"))))
    (should (equal (nitpick-diff-hl--default-base "/tmp/wt") "trunk"))))

(ert-deftest nitpick-test-suggested-base-is-nil-when-nothing-answers ()
  "Nothing to suggest is not an error: the prompt opens with no default."
  (let ((nitpick-diff-hl--bases nil))
    (nitpick-test--with-stubs
        ((nitpick--pr-ctx (lambda (&rest _) (error "gh pr view failed")))
         (magit-main-branch (lambda () nil))
         (magit-git-string (lambda (&rest _) nil)))
      (should-not (nitpick-diff-hl--suggested-base "/tmp/wt")))))

(provide 'nitpick-test)
;;; nitpick-test.el ends here
