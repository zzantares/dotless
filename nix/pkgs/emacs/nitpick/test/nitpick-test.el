;;; nitpick-test.el --- Tests for nitpick -*- lexical-binding: t; -*-

;;; Commentary:

;; Hermetic ERT suite: no network, no `gh', no magit, no forge.  Stubs stand in
;; for the process boundary and record what would have been sent, so the tests
;; assert on the GraphQL query and variables rather than on a live PR.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'nitpick)
(require 'nitpick-tree)

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

(defvar diff-hl-fringe-flat-bmp)
(defvar diff-hl-fringe-face-function)

(defvar diff-hl-spec-cache)

(ert-deftest nitpick-test-diff-hl-line-mode-forgets-cached-specs ()
  "diff-hl caches a fringe spec per change type and hands the same one back,
so the cache has to go when the bitmap a removal gets changes."
  (let ((diff-hl-spec-cache (make-hash-table :test 'equal)))
    (puthash '(delete nil left) "stale" diff-hl-spec-cache)
    (nitpick-test--with-diff-hl
      (nitpick-diff-hl-line-mode 1)
      (should (zerop (hash-table-count diff-hl-spec-cache)))
      (puthash '(delete nil left) "stale again" diff-hl-spec-cache)
      (nitpick-diff-hl-line-mode -1)
      (should (zerop (hash-table-count diff-hl-spec-cache))))))

(ert-deftest nitpick-test-diff-hl-removals-get-a-visible-bitmap ()
  "A removal has no line background to be seen by, so it needs the fringe."
  (nitpick-test--with-diff-hl
    (let ((diff-hl-fringe-flat-bmp 'diff-hl-bmp-empty)
          (nitpick-diff-hl-delete-bmp 'zz-visible)
          seen)
      (nitpick-test--with-stubs
          ((diff-hl-highlight-on-fringe-flat
            (lambda (&rest _) (push diff-hl-fringe-flat-bmp seen))))
        (nitpick-test--in-buffer
          (let ((ovl (nitpick-test--line-overlay 2)))
            (nitpick-diff-hl-highlight-line-flat ovl 'delete 'single)
            (nitpick-diff-hl-highlight-line-flat ovl 'insert 'single))))
      ;; the removal is drawn with the visible one, the rest stay flat
      (should (equal seen '(diff-hl-bmp-empty zz-visible))))))

(ert-deftest nitpick-test-diff-hl-removals-carry-their-own-colour ()
  "`diff-hl-delete' is colourless in plenty of themes, so the marker brings
its own face rather than inheriting whatever the fringe paints with."
  (nitpick-test--with-diff-hl
    (let (seen)
      (nitpick-test--with-stubs
          ((diff-hl-highlight-on-fringe-flat
            (lambda (&rest _)
              (push (funcall diff-hl-fringe-face-function 'delete nil) seen))))
        (nitpick-test--in-buffer
          (let ((ovl (nitpick-test--line-overlay 2))
                (diff-hl-fringe-face-function #'ignore))
            (nitpick-diff-hl-highlight-line-flat ovl 'delete 'single)
            ;; and a change is left to diff-hl's own face function
            (nitpick-diff-hl-highlight-line-flat ovl 'change 'single))))
      (should (equal seen '(nil nitpick-diff-hl-delete))))))

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
            ;; the revision resolves; what diff-hl is pointed at is the
            ;; revision itself, so this only has to be non-nil
            (magit-rev-verify (lambda (_) "cafe1234")))
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

(ert-deftest nitpick-test-diff-hl-set-base-repaints-the-project ()
  "diff-hl's own update after a reference change paints nothing, so a repaint
of the project is scheduled on top of it."
  (nitpick-test--with-set-base
    (let (repainted)
      (nitpick-test--with-stubs
          ((nitpick-diff-hl--repaint (lambda (proj) (setq repainted (list proj)))))
        (nitpick-diff-hl-set-base "/tmp/wt/" "master")
        (should (equal repainted '((transient . "/tmp/wt/"))))))))

(ert-deftest nitpick-test-diff-hl-repaint-waits-for-the-command-to-return ()
  "The redraw runs from an idle timer, not inside the setting command."
  (let (timer-args)
    (nitpick-test--with-stubs
        ((run-with-idle-timer (lambda (&rest args) (setq timer-args args))))
      (nitpick-diff-hl--repaint nil)
      (should (equal (seq-take timer-args 2) '(0 nil)))
      (should (functionp (nth 2 timer-args))))))

(ert-deftest nitpick-test-diff-hl-repaint-updates-one-buffer-at-a-time ()
  "Synchronously: diff-hl's async diffs share two fixed buffer names, so
concurrent updates overwrite each other's results."
  (let ((painted (generate-new-buffer " *nitpick-test-painted*"))
        (scratch (generate-new-buffer " *nitpick-test-no-file*"))
        timer-fn seen)
    (unwind-protect
        (progn
          (with-current-buffer painted
            (setq buffer-file-name "/tmp/wt/painted.el")
            (setq-local diff-hl-mode t))
          (with-current-buffer scratch (setq-local diff-hl-mode t))
          (nitpick-test--with-stubs
              ((run-with-idle-timer (lambda (_ _ fn) (setq timer-fn fn)))
               (buffer-list (lambda (&optional _) (list painted scratch)))
               (diff-hl-update
                (lambda () (push (cons (buffer-name) diff-hl-update-async) seen))))
            (let ((diff-hl-update-async t))
              (nitpick-diff-hl--repaint nil)
              (funcall timer-fn))))
      (kill-buffer painted)
      (kill-buffer scratch))
    ;; the buffer with a file, with async off; the one without a file skipped
    (should (equal seen '((" *nitpick-test-painted*" . nil))))))

(ert-deftest nitpick-test-diff-hl-set-base-remembers-the-revision ()
  (nitpick-test--with-set-base
    (nitpick-diff-hl-set-base "/tmp/wt" "develop")
    ;; keyed by one spelling, so a root without the trailing slash still hits
    (should (equal (nitpick-diff-hl--suggested-base "/tmp/wt/") "develop"))))

(ert-deftest nitpick-test-diff-hl-set-base-points-at-the-revision-itself ()
  "The default is `git diff REVISION': its tip, as typed, and no merge-base."
  (nitpick-test--with-set-base
    (nitpick-test--with-stubs
        ((magit-git-string
          (lambda (&rest args) (setq nitpick-test--merge-base-args args) "cafe1234")))
      (setq nitpick-test--merge-base-args nil)
      ;; no remote glued on: origin/master and master are different answers
      (nitpick-diff-hl-set-base "/tmp/wt/" "origin/master")
      (should (equal nitpick-test--pointed-at "origin/master"))
      (nitpick-diff-hl-set-base "/tmp/wt/" "master")
      (should (equal nitpick-test--pointed-at "master"))
      ;; and HEAD is just one of the revisions you can pick
      (nitpick-diff-hl-set-base "/tmp/wt/" "HEAD")
      (should (equal nitpick-test--pointed-at "HEAD"))
      ;; git was never asked for a merge-base along the way
      (should-not nitpick-test--merge-base-args))))

(ert-deftest nitpick-test-diff-hl-set-base-takes-three-dots-for-the-merge-base ()
  "The explicit case, spelled as git spells it."
  (nitpick-test--with-set-base
    (nitpick-test--with-stubs
        ((magit-git-string
          (lambda (&rest args) (setq nitpick-test--merge-base-args args) "cafe1234")))
      (nitpick-diff-hl-set-base "/tmp/wt/" "master...")
      (should (equal nitpick-test--merge-base-args '("merge-base" "master" "HEAD")))
      ;; and what diff-hl gets is the fork point, not the branch
      (should (equal nitpick-test--pointed-at "cafe1234")))))

(ert-deftest nitpick-test-diff-hl-set-base-remembers-the-three-dots ()
  "The prompt comes back with the range you asked for, not what it resolved to."
  (nitpick-test--with-set-base
    (nitpick-diff-hl-set-base "/tmp/wt/" "master...")
    (should (equal (nitpick-diff-hl--suggested-base "/tmp/wt/") "master..."))))

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
  (should (eq (lookup-key nitpick-prefix-map "H") #'nitpick-diff-hl-line-mode))
  (should (eq (lookup-key nitpick-prefix-map "t") #'nitpick-tree)))

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

;; `defvar' with no value marks a variable special only inside the file that
;; writes it, so the bindings below need their own declaration to be dynamic.
(defvar vc-git-diff-switches)

(ert-deftest nitpick-test-zero-context-forces-u0 ()
  "The switch diff-hl's parser assumes, which its own binding does not deliver."
  (let ((vc-git-diff-switches '("--histogram" "--stat" "-U5"))
        seen)
    (apply #'nitpick--zero-context
           (lambda (&rest _) (setq seen vc-git-diff-switches))
           '("f" Git))
    ;; -U0 first, the algorithm switch kept, the format ones dropped
    (should (equal seen '("-U0" "--histogram")))))

(ert-deftest nitpick-test-zero-context-survives-an-unset-switch-list ()
  "t and void both mean no list of switches; neither may leak into the call."
  (let ((vc-git-diff-switches t) seen)
    (apply #'nitpick--zero-context
           (lambda (&rest _) (setq seen vc-git-diff-switches))
           '("f" Git))
    (should (equal seen '("-U0")))))

(defun nitpick-test--zero-context-advised ()
  "The diff-hl functions currently carrying the zero-context advice."
  (seq-filter (lambda (entry)
                (advice-member-p #'nitpick--zero-context (cdr entry)))
              nitpick--diff-hl-diff-functions))

(ert-deftest nitpick-test-zero-context-mode-adds-and-removes-its-advice ()
  "Both functions, not just the one flydiff overrides away."
  (nitpick-test--with-stubs ((featurep (lambda (_) t)))
    (nitpick-diff-hl-zero-context-mode 1)
    (should (equal (nitpick-test--zero-context-advised)
                   nitpick--diff-hl-diff-functions))
    (nitpick-diff-hl-zero-context-mode -1)
    (should-not (nitpick-test--zero-context-advised))))

(ert-deftest nitpick-test-zero-context-mode-waits-for-each-feature ()
  "Advice added before a feature loads is listed but never runs, so the mode
defers one wrapping per feature instead."
  (let (deferred)
    (nitpick-test--with-stubs
        ((featurep (lambda (_) nil))
         (eval-after-load (lambda (file fn) (push (cons file fn) deferred))))
      (nitpick-diff-hl-zero-context-mode 1))
    (unwind-protect
        (progn
          (should (equal (sort (mapcar #'car deferred) #'string<)
                         (sort (mapcar #'car nitpick--diff-hl-diff-functions) #'string<)))
          (should-not (nitpick-test--zero-context-advised))
          ;; the loads arrive, and only then is each wrapped
          (dolist (d deferred) (funcall (cdr d)))
          (should (equal (nitpick-test--zero-context-advised)
                         nitpick--diff-hl-diff-functions)))
      (nitpick-diff-hl-zero-context-mode -1))))

(ert-deftest nitpick-test-zero-context-mode-turned-off-before-the-load-stays-off ()
  (let (deferred)
    (nitpick-test--with-stubs
        ((featurep (lambda (_) nil))
         (eval-after-load (lambda (file fn) (push (cons file fn) deferred))))
      (nitpick-diff-hl-zero-context-mode 1))
    (nitpick-diff-hl-zero-context-mode -1)
    (dolist (d deferred) (funcall (cdr d)))
    (should-not (nitpick-test--zero-context-advised))))

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
         ;; the graph has nothing to offer either: that is this test's premise
         (nitpick--nearest-base (lambda (&rest _) nil))
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
         (nitpick--nearest-base (lambda (&rest _) nil))
         (magit-main-branch (lambda () nil))
         (magit-git-string (lambda (&rest _) nil)))
      (should-not (nitpick-diff-hl--suggested-base "/tmp/wt")))))

;;;; Changed-file tree: reading git

(defun nitpick-test--nul (&rest fields)
  "Return FIELDS as git writes them with `-z': NUL after every one.
Spelled out rather than written into the string literals, where a NUL ahead
of a digit reads as one octal escape."
  (mapconcat (lambda (field) (concat field "\0")) fields ""))

(defun nitpick-test--git-stub (table)
  "Return a `nitpick-tree--git-output' stub answering from TABLE.
TABLE is an alist keyed by the git subcommand and its first switch, so one
stub can answer the three calls a tree needs."
  (lambda (&rest args)
    (or (cdr (assoc (format "%s %s" (nth 0 args) (nth 1 args)) table)) "")))

(ert-deftest nitpick-test-tree-parses-name-status ()
  "A NUL-separated status and path per file."
  (should (equal (nitpick-tree--parse-name-status
                  (nitpick-test--nul "M" "a.el" "A" "dir/b.el"))
                 '(("a.el" "M") ("dir/b.el" "A")))))

(ert-deftest nitpick-test-tree-name-status-keeps-the-new-path-of-a-rename ()
  "A rename names the old path then the new one; the new one is the file."
  (should (equal (nitpick-tree--parse-name-status
                  (nitpick-test--nul "R100" "old.el" "new.el" "M" "c.el"))
                 '(("new.el" "R100" "old.el") ("c.el" "M")))))

(ert-deftest nitpick-test-tree-name-status-of-an-empty-diff-is-empty ()
  "Nothing changed is not a parse error."
  (should-not (nitpick-tree--parse-name-status "")))

(ert-deftest nitpick-test-tree-parses-numstat ()
  "Counts and path share one field, TAB separated."
  (should (equal (nitpick-tree--parse-numstat
                  (nitpick-test--nul "3\t1\ta.el" "12\t0\tdir/b.el"))
                 '(("a.el" 3 1) ("dir/b.el" 12 0)))))

(ert-deftest nitpick-test-tree-numstat-counts-a-binary-file-as-nil ()
  "git writes `-' for both counts of a binary file rather than a number."
  (should (equal (nitpick-tree--parse-numstat (nitpick-test--nul "-\t-\tlogo.png"))
                 '(("logo.png" nil nil)))))

(ert-deftest nitpick-test-tree-numstat-of-a-rename-reads-the-two-paths-after-it ()
  "A rename ends its field after the counts: the empty path is the marker."
  (should (equal (nitpick-tree--parse-numstat
                  ;; The counts, an empty path, then the two paths.
                  (nitpick-test--nul "4\t2\t" "old.el" "new.el" "5\t0\tc.el"))
                 '(("new.el" 4 2) ("c.el" 5 0)))))

(ert-deftest nitpick-test-tree-changes-joins-the-status-with-the-counts ()
  "Both git calls describe the same file; the tree wants them as one plist."
  (nitpick-test--with-stubs
      ((nitpick-tree--git-output
        (nitpick-test--git-stub
         `(("diff --name-status" . ,(nitpick-test--nul "M" "a.el"))
           ("diff --numstat" . ,(nitpick-test--nul "3\t1\ta.el"))))))
    (should (equal (nitpick-tree--changes "/tmp/wt" "origin/master")
                   '((:file "a.el" :status "M" :from nil
                      :added 3 :deleted 1 :binary nil))))))

(ert-deftest nitpick-test-tree-changes-marks-a-binary-file ()
  "Counted by neither side, but git did diff it: that is not `untracked'."
  (nitpick-test--with-stubs
      ((nitpick-tree--git-output
        (nitpick-test--git-stub
         `(("diff --name-status" . ,(nitpick-test--nul "M" "logo.png"))
           ("diff --numstat" . ,(nitpick-test--nul "-\t-\tlogo.png"))))))
    (should (plist-get (car (nitpick-tree--changes "/tmp/wt" "HEAD")) :binary))))

(ert-deftest nitpick-test-tree-changes-appends-the-untracked-files ()
  "A file never added is absent from every diff, and still worth listing."
  (let ((nitpick-tree-show-untracked t))
    (nitpick-test--with-stubs
        ((nitpick-tree--git-output
          (nitpick-test--git-stub
           `(("diff --name-status" . ,(nitpick-test--nul "M" "a.el"))
             ("diff --numstat" . ,(nitpick-test--nul "3\t1\ta.el"))
             ("ls-files --others" . ,(nitpick-test--nul "new.el"))))))
      (let ((files (nitpick-tree--changes "/tmp/wt" "HEAD")))
        (should (equal (mapcar (lambda (f) (plist-get f :file)) files)
                       '("a.el" "new.el")))
        (should (equal (plist-get (nth 1 files) :status) "?"))
        (should-not (plist-get (nth 1 files) :added))))))

(ert-deftest nitpick-test-tree-changes-can-leave-the-untracked-files-out ()
  "The option off means only what git diffs, which is what the forge shows."
  (let ((nitpick-tree-show-untracked nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--git-output
          (nitpick-test--git-stub
           `(("diff --name-status" . ,(nitpick-test--nul "M" "a.el"))
             ("diff --numstat" . ,(nitpick-test--nul "3\t1\ta.el"))
             ("ls-files --others" . ,(nitpick-test--nul "new.el"))))))
      (should (equal (mapcar (lambda (f) (plist-get f :file))
                             (nitpick-tree--changes "/tmp/wt" "HEAD"))
                     '("a.el"))))))

;;;; Changed-file tree: folding the paths

(defun nitpick-test--shape (nodes)
  "Return NODES as nested (NAME . CHILDREN) conses, or NAME for a file."
  (mapcar (lambda (node)
            (if (plist-get node :dir)
                (cons (plist-get node :name)
                      (nitpick-test--shape (plist-get node :children)))
              (plist-get node :name)))
          nodes))

(ert-deftest nitpick-test-tree-build-nests-files-under-their-directories ()
  "Files sharing a directory are one node's children, not two paths."
  (let ((nitpick-tree-collapse-dirs nil))
    (should (equal (nitpick-test--shape
                    (nitpick-tree--build '((:file "src/a.el") (:file "src/b.el")
                                           (:file "README.md"))
                                         "/tmp/wt"))
                   '(("src" "a.el" "b.el") "README.md")))))

(ert-deftest nitpick-test-tree-build-sorts-directories-before-files ()
  "Directories first, each group by name, as treemacs draws a real tree."
  (let ((nitpick-tree-collapse-dirs nil))
    (should (equal (nitpick-test--shape
                    (nitpick-tree--build '((:file "z.el") (:file "a.el")
                                           (:file "zz/c.el") (:file "aa/c.el"))
                                         "/tmp/wt"))
                   '(("aa" "c.el") ("zz" "c.el") "a.el" "z.el")))))

(ert-deftest nitpick-test-tree-build-gives-a-file-its-absolute-path ()
  "The node is visited by path, so it is the real file, not the git one."
  (let ((node (car (nitpick-tree--build '((:file "src/a.el")) "/tmp/wt"))))
    (should (equal (plist-get (car (plist-get node :children)) :path)
                   "/tmp/wt/src/a.el"))))

(ert-deftest nitpick-test-tree-build-collapses-a-chain-of-single-directories ()
  "Three directories holding nothing but each other are one line."
  (let ((nitpick-tree-collapse-dirs t))
    (should (equal (nitpick-test--shape
                    (nitpick-tree--build '((:file "nix/pkgs/emacs/a.el")) "/tmp/wt"))
                   '(("nix/pkgs/emacs" "a.el"))))))

(ert-deftest nitpick-test-tree-build-stops-collapsing-where-a-directory-branches ()
  "A directory with two children is where the chain ends."
  (let ((nitpick-tree-collapse-dirs t))
    (should (equal (nitpick-test--shape
                    (nitpick-tree--build '((:file "nix/pkgs/a/x.el")
                                           (:file "nix/pkgs/b/y.el"))
                                         "/tmp/wt"))
                   '(("nix/pkgs" ("a" "x.el") ("b" "y.el")))))))

(ert-deftest nitpick-test-tree-build-leaves-the-chain-alone-when-told-to ()
  "The option off draws every directory on its own line."
  (let ((nitpick-tree-collapse-dirs nil))
    (should (equal (nitpick-test--shape
                    (nitpick-tree--build '((:file "nix/pkgs/a.el")) "/tmp/wt"))
                   '(("nix" ("pkgs" "a.el")))))))

(ert-deftest nitpick-test-tree-collapsed-node-keeps-the-deepest-path ()
  "The folded line stands for the last directory, so that is its path."
  (let* ((nitpick-tree-collapse-dirs t)
         (node (car (nitpick-tree--build '((:file "nix/pkgs/a.el")) "/tmp/wt"))))
    (should (equal (plist-get node :path) "/tmp/wt/nix/pkgs"))))

;;;; Changed-file tree: what a line says

(ert-deftest nitpick-test-tree-label-omits-the-marker-of-a-modification ()
  "`M' is most of a review; the counts already say it changed."
  (should (equal (substring-no-properties
                  (nitpick-tree--label '(:name "a.el" :status "M" :added 3 :deleted 1)))
                 "a.el +3 -1")))

(ert-deftest nitpick-test-tree-label-marks-anything-other-than-a-modification ()
  "Added, deleted, untracked: one letter, git's own."
  (should (equal (substring-no-properties
                  (nitpick-tree--label '(:name "a.el" :status "A" :added 9 :deleted 0)))
                 "a.el A +9"))
  (should (equal (substring-no-properties
                  (nitpick-tree--label '(:name "new.el" :status "?")))
                 "new.el ?")))

(ert-deftest nitpick-test-tree-label-names-where-a-rename-came-from ()
  "The marker says it moved; only the old path says what it was."
  (should (equal (substring-no-properties
                  (nitpick-tree--label
                   '(:name "new.el" :status "R100" :from "src/old.el"
                     :added 1 :deleted 1)))
                 "new.el R +1 -1 <- src/old.el")))

(ert-deftest nitpick-test-tree-label-says-bin-instead-of-counting-a-binary ()
  "git will not count it, so neither does the pane."
  (should (equal (substring-no-properties
                  (nitpick-tree--label '(:name "logo.png" :status "M" :binary t)))
                 "logo.png bin")))

(ert-deftest nitpick-test-tree-label-of-a-directory-is-its-name ()
  "No counts on a directory: the files under it carry them."
  (should (equal (substring-no-properties
                  (nitpick-tree--label '(:name "src" :dir t)))
                 "src")))

(ert-deftest nitpick-test-tree-totals-add-up-the-counted-files ()
  "An untracked or binary file counts as a file and adds no lines."
  (should (equal (nitpick-tree--totals '((:file "a.el" :added 3 :deleted 1)
                                         (:file "b.el" :added 2 :deleted 0)
                                         (:file "new.el")))
                 '(3 5 1))))

(ert-deftest nitpick-test-tree-header-names-the-revision-and-the-totals ()
  "What is being compared, said once, where it cannot scroll away."
  (should (equal (substring-no-properties
                  (nitpick-tree--header "origin/master..." '(2 5 1)))
                 " vs origin/master...  2 files +5 -1")))

(ert-deftest nitpick-test-tree-header-says-file-for-one-file ()
  "One file, not one files."
  (should (string-match-p "1 file "
                          (substring-no-properties
                           (nitpick-tree--header "HEAD" '(1 1 0))))))

;;;; Changed-file tree: the diff view

(ert-deftest nitpick-test-tree-diff-paths-of-a-file-is-the-one-path ()
  "Nothing clever for the common case."
  (should (equal (nitpick-tree--diff-paths '(:file "src/a.el") "/tmp/wt")
                 '("src/a.el"))))

(ert-deftest nitpick-test-tree-diff-paths-of-a-rename-names-both-sides ()
  "git pairs the two paths to see the rename; asking for one shows an add."
  (should (equal (nitpick-tree--diff-paths
                  '(:file "new.el" :from "src/old.el") "/tmp/wt")
                 '("new.el" "src/old.el"))))

(ert-deftest nitpick-test-tree-diff-paths-of-a-directory-is-its-subtree ()
  "A directory node diffs everything under it, named relative to the root."
  (should (equal (nitpick-tree--diff-paths
                  '(:dir t :name "pkgs" :path "/tmp/wt/nix/pkgs") "/tmp/wt")
                 '("nix/pkgs"))))

(ert-deftest nitpick-test-tree-diff-refuses-an-untracked-file ()
  "git holds no version of it, so there is no diff to show - say so."
  (let ((buffer (generate-new-buffer " *nitpick-test-pane*")))
    (unwind-protect
        (with-current-buffer buffer
          (setq-local nitpick-tree--root "/tmp/wt"
                      nitpick-tree--revision "master")
          (nitpick-test--with-stubs
              ((nitpick-tree--node-at-point
                (lambda () '(:file "new.el" :status "?")))
               (magit-diff-range (lambda (&rest _) (error "should not be called"))))
            (should-error (nitpick-tree-visit-diff) :type 'user-error)))
      (kill-buffer buffer))))

(ert-deftest nitpick-test-tree-diff-asks-magit-for-the-panes-revision ()
  "The same revision the pane lists, so the diff agrees with what it says."
  (let ((buffer (generate-new-buffer " *nitpick-test-pane*"))
        (sent nil))
    (unwind-protect
        (with-current-buffer buffer
          (setq-local nitpick-tree--root "/tmp/wt"
                      nitpick-tree--revision "origin/master")
          (nitpick-test--with-stubs
              ((nitpick-tree--node-at-point
                (lambda () '(:file "src/a.el" :status "M")))
               ;; (ARGS FILES), as magit answers outside a transient: it
               ;; fills both interactive slots, and its FILES is the last
               ;; diff's, which must not reach git as a revision.
               (magit-diff-arguments (lambda (&rest _) '(("--stat") ("stale.el"))))
               (magit-diff-range (lambda (rev args files)
                                   (setq sent (list rev args files)))))
            (nitpick-tree-visit-diff)
            (should (equal sent '("origin/master" ("--stat") ("src/a.el"))))))
      (kill-buffer buffer))))

(ert-deftest nitpick-test-tree-diff-resolves-a-merge-base-revision ()
  "A trailing `...' is the merge base here too, as everywhere in nitpick."
  (let ((buffer (generate-new-buffer " *nitpick-test-pane*"))
        (sent nil))
    (unwind-protect
        (with-current-buffer buffer
          (setq-local nitpick-tree--root "/tmp/wt"
                      nitpick-tree--revision "origin/master...")
          (nitpick-test--with-stubs
              ((nitpick-tree--node-at-point
                (lambda () '(:file "a.el" :status "M")))
               (magit-diff-arguments (lambda (&rest _) '(nil nil)))
               (magit-git-string (lambda (&rest args)
                                   (and (equal (car args) "merge-base") "abc123")))
               (magit-diff-range (lambda (rev _args _files) (setq sent rev))))
            (nitpick-tree-visit-diff)
            (should (equal sent "abc123"))))
      (kill-buffer buffer))))

(ert-deftest nitpick-test-tree-pane-binds-d-to-the-diff ()
  "`d' is diff in the pane, not `treemacs-delete-file'."
  (should (eq (lookup-key nitpick-tree-mode-map "d") #'nitpick-tree-visit-diff)))

(ert-deftest nitpick-test-tree-pane-refreshes-by-re-reading-the-diff ()
  "`treemacs-refresh' would redraw the same nodes and claim success."
  (should (eq (lookup-key nitpick-tree-mode-map "r") #'nitpick-tree-refresh))
  (should (eq (lookup-key nitpick-tree-mode-map "g") #'nitpick-tree-refresh)))

;;;; Changed-file tree: which window a file opens in

(defmacro nitpick-test--with-windows (names &rest body)
  "Run BODY with a fresh single-window layout and NAMES bound to new buffers."
  (declare (indent 1))
  `(let ,(mapcar (lambda (n) `(,n (generate-new-buffer ,(format "*nitpick-test-%s*" n))))
                 names)
     (unwind-protect
         (save-window-excursion (delete-other-windows) ,@body)
       ,@(mapcar (lambda (n) `(kill-buffer ,n)) names))))

(ert-deftest nitpick-test-tree-visit-reuses-the-window-already-showing-the-file ()
  "Opening a file twice must not put a second copy of it on screen."
  (nitpick-test--with-windows (file)
    (let ((other (split-window)))
      (set-window-buffer other file)
      (should (eq (nitpick-tree--visit-window file) other)))))

(ert-deftest nitpick-test-tree-visit-picks-the-last-used-window ()
  "Not the pane: `display-buffer' cannot use a side window and splits instead."
  (nitpick-test--with-windows (file)
    (let* ((pane (selected-window))
           (work (split-window)))
      (select-window work)
      (select-window pane)
      (should (eq (nitpick-tree--visit-window file) work)))))

(ert-deftest nitpick-test-tree-visit-finds-no-window-when-it-is-alone ()
  "Nothing to reuse, so the caller falls back to `display-buffer'."
  (nitpick-test--with-windows (file)
    (should-not (nitpick-tree--visit-window file))))

;;;; diff-hl: inferring the base from the commit graph

(ert-deftest nitpick-test-nearest-branch-takes-the-closest-merge-base ()
  "The branch HEAD left last is the one whose merge base is nearest to it."
  (should (equal (nitpick--nearest-branch '(("master" . 9) ("feat-a" . 2)) "master")
                 "feat-a")))

(ert-deftest nitpick-test-nearest-branch-gives-a-tie-to-the-main-branch ()
  "A fast-forward merge leaves a branch's tip on the fork point, tying with
master; order of listing must not decide it."
  (should (equal (nitpick--nearest-branch
                  '(("emacs-forge-tiling" . 1) ("master" . 1)) "master")
                 "master"))
  ;; and the other way round, so it is the rule deciding and not the order
  (should (equal (nitpick--nearest-branch
                  '(("master" . 1) ("emacs-forge-tiling" . 1)) "master")
                 "master")))

(ert-deftest nitpick-test-nearest-branch-keeps-a-closer-branch-over-main ()
  "A real stack parent is strictly closer, so the tie rule never reaches it."
  (should (equal (nitpick--nearest-branch '(("master" . 2) ("feat-a" . 1)) "master")
                 "feat-a")))

(ert-deftest nitpick-test-nearest-branch-of-nothing-is-nothing ()
  "No candidate is not an error."
  (should-not (nitpick--nearest-branch nil "master")))

(defun nitpick-test--graph-stubs (head graph &optional merged)
  "Return stubs answering for HEAD over GRAPH, an alist of (BRANCH MB DISTANCE).
MERGED is the branches `git branch --merged' would list."
  (list (cons 'magit-get-current-branch (lambda () head))
        (cons 'magit-rev-parse (lambda (&rest _) "headsha"))
        (cons 'magit-list-local-branch-names (lambda () (mapcar #'car graph)))
        (cons 'magit-git-lines (lambda (&rest _) merged))
        (cons 'magit-git-string
              (lambda (&rest args)
                (pcase args
                  (`("merge-base" "HEAD" ,branch) (nth 1 (assoc branch graph)))
                  (`("rev-list" "--count" ,range)
                   (let ((base (car (split-string range "\\.\\."))))
                     (number-to-string
                      (or (nth 2 (seq-find (lambda (g) (equal (nth 1 g) base)) graph))
                          0))))
                  (_ nil))))))

(ert-deftest nitpick-test-base-candidates-drops-branches-merged-into-main ()
  "Finished work is not what this branch was made from."
  (nitpick-test--call-with-stubs
   (nitpick-test--graph-stubs
    "mine"
    '(("master" "forkpoint" 1) ("done" "forkpoint" 1) ("mine" "headsha" 0))
    '("done"))
   (lambda ()
     (should (equal (nitpick--base-candidates "master") '(("master" . 1)))))))

(ert-deftest nitpick-test-base-candidates-drops-a-branch-built-on-this-one ()
  "A branch whose merge base is HEAD itself sits above it, not under it."
  (nitpick-test--call-with-stubs
   (nitpick-test--graph-stubs
    "mine"
    '(("master" "forkpoint" 3) ("child" "headsha" 0) ("mine" "headsha" 0)))
   (lambda ()
     (should (equal (nitpick--base-candidates "master") '(("master" . 3)))))))

(ert-deftest nitpick-test-nearest-base-appends-the-merge-base-suffix ()
  "What the branch changed since it left, not how far its base has moved."
  (nitpick-test--call-with-stubs
   (append
    (nitpick-test--graph-stubs
     "feat-b" '(("master" "forkpoint" 4) ("feat-a" "atip" 1) ("feat-b" "headsha" 0)))
    (list (cons 'nitpick-diff-hl--default-base (lambda (&rest _) "master"))
          (cons 'magit-git-success (lambda (&rest _) nil))))
   (lambda ()
     (should (equal (nitpick--nearest-base "/tmp/wt") "feat-a...")))))

(ert-deftest nitpick-test-nearest-base-is-nil-on-the-main-branch ()
  "master was not made from anything: there is nothing to infer."
  (nitpick-test--call-with-stubs
   (list (cons 'magit-get-current-branch (lambda () "master"))
         (cons 'nitpick-diff-hl--default-base (lambda (&rest _) "master")))
   (lambda () (should-not (nitpick--nearest-base "/tmp/wt")))))

(ert-deftest nitpick-test-nearest-base-of-a-merged-branch-is-main ()
  "Nothing of its own is left, so let the answer be the empty diff it is."
  (nitpick-test--call-with-stubs
   (list (cons 'magit-get-current-branch (lambda () "landed"))
         (cons 'nitpick-diff-hl--default-base (lambda (&rest _) "master"))
         (cons 'magit-git-success (lambda (&rest _) t)))
   (lambda () (should (equal (nitpick--nearest-base "/tmp/wt") "master...")))))

(ert-deftest nitpick-test-suggested-base-prefers-the-forge-over-the-graph ()
  "The forge knows the base; the graph only has evidence for it."
  (let ((nitpick-diff-hl--bases nil))
    (nitpick-test--with-stubs
        ((nitpick--pr-ctx (lambda (&rest _) '((base . "feature/parent"))))
         (nitpick--nearest-base (lambda (&rest _) "guessed..."))
         (magit-main-branch (lambda () "master")))
      (should (equal (nitpick-diff-hl--suggested-base "/tmp/wt")
                     "origin/feature/parent")))))

(ert-deftest nitpick-test-suggested-base-prefers-the-graph-over-the-remote-head ()
  "A remote-tracking ref is only as current as the last fetch."
  (let ((nitpick-diff-hl--bases nil))
    (nitpick-test--with-stubs
        ((nitpick--pr-ctx (lambda (&rest _) (error "gh pr view failed")))
         (nitpick--nearest-base (lambda (&rest _) "master..."))
         (magit-main-branch (lambda () "master")))
      (should (equal (nitpick-diff-hl--suggested-base "/tmp/wt") "master...")))))

;;;; Changed-file tree: painting what it lists

(ert-deftest nitpick-test-tree-paint-turns-on-the-line-mode ()
  "Opening the pane spares you `nitpick-diff-hl-line-mode' by hand."
  (let ((nitpick-tree-paint-lines t)
        (called nil))
    ;; diff-hl is not in the suite's load path, and `nitpick-tree--paint' is
    ;; right to stop without it: say it is there instead of loading it.
    (nitpick-test--with-stubs
        ((nitpick-tree--diff-hl-available-p (lambda () t))
         (nitpick-diff-hl-line-mode (lambda (&rest args) (setq called args))))
      (let ((nitpick-diff-hl-line-mode nil))
        (nitpick-tree--paint)
        (should (equal called '(1)))))))

(ert-deftest nitpick-test-tree-paint-does-nothing-without-diff-hl ()
  "The line mode reads diff-hl's highlight slots as it starts, so it cannot
run before diff-hl has defined them."
  (let ((nitpick-tree-paint-lines t)
        (called nil))
    (nitpick-test--with-stubs
        ((nitpick-diff-hl-line-mode (lambda (&rest args) (setq called args))))
      (let ((nitpick-diff-hl-line-mode nil))
        (nitpick-tree--paint)
        (should-not called)))))

(ert-deftest nitpick-test-tree-paint-leaves-the-line-mode-alone-when-on ()
  "Already painting: nothing to do, and no redraw to pay for."
  (let ((nitpick-tree-paint-lines t)
        (called nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--diff-hl-available-p (lambda () t))
         (nitpick-diff-hl-line-mode (lambda (&rest args) (setq called args))))
      (let ((nitpick-diff-hl-line-mode t))
        (nitpick-tree--paint)
        (should-not called)))))

(ert-deftest nitpick-test-tree-paint-obeys-its-option ()
  "The option is how you say no to both halves of the painting."
  (let ((nitpick-tree-paint-lines nil)
        (called nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--diff-hl-available-p (lambda () t))
         (nitpick-diff-hl-line-mode (lambda (&rest args) (setq called args))))
      (let ((nitpick-diff-hl-line-mode nil))
        (nitpick-tree--paint)
        (should-not called)))))

(ert-deftest nitpick-test-tree-paint-buffer-turns-diff-hl-on-locally ()
  "A file with diff-hl off has nothing to show, whatever the line mode does."
  (let ((nitpick-tree-paint-lines t)
        (called nil))
    (nitpick-test--with-stubs
        ((diff-hl-mode (lambda (&rest args) (setq called args))))
      (with-temp-buffer
        (setq buffer-file-name "/tmp/wt/a.el")
        (let ((diff-hl-mode nil))
          (nitpick-tree--paint-buffer)
          (should (equal called '(1))))))))

(ert-deftest nitpick-test-tree-paint-buffer-skips-what-is-not-a-file ()
  "Nothing to diff in a buffer with no file behind it."
  (let ((nitpick-tree-paint-lines t)
        (called nil))
    (nitpick-test--with-stubs
        ((diff-hl-mode (lambda (&rest args) (setq called args))))
      (with-temp-buffer
        (let ((diff-hl-mode nil))
          (nitpick-tree--paint-buffer)
          (should-not called))))))

(provide 'nitpick-test)
;;; nitpick-test.el ends here
