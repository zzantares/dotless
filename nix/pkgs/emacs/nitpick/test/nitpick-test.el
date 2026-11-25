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
(require 'nitpick-pr)

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

(defun nitpick-test--messaged (thunk)
  "Return what THUNK reported through `message\=', as one string."
  (let ((inhibit-message t))
    (with-temp-buffer
      (let ((standard-output (current-buffer))
            (message-log-max nil))
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args) (insert (apply #'format fmt args)))))
          (funcall thunk)))
      (buffer-string))))

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

;;;; Diff-buffer targets

(defun nitpick-test--in-hunk (text from to fn &optional combined)
  "Call FN with a fake hunk section over TEXT, in a buffer holding TEXT.
TEXT is a hunk body, one diff line per line; FROM and TO are its header's
`(START LEN)' ranges.  `nitpick--oref' reads the section as an alist, so the
suite never needs magit's classes.  COMBINED fills the slot of that name."
  (with-temp-buffer
    (insert text)
    (let ((section `((type . hunk)
                     (combined . ,combined)
                     (content . ,(point-min))
                     (end . ,(point-max))
                     (from-range . ,from)
                     (to-range . ,to)
                     (parent . ((value . "src/thing.el"))))))
      (nitpick-test--with-stubs
          ((nitpick--oref (lambda (obj slot) (alist-get slot obj))))
        (funcall fn section)))))

(defconst nitpick-test--hunk
  (concat " keep\n"
          "-gone\n"
          "+added\n"
          "+also added\n"
          " tail\n")
  "A hunk body of @@ -10,3 +10,4 @@: context, a removal, two additions, context.")

(ert-deftest nitpick-test-hunk-body-numbers-both-sides ()
  (nitpick-test--in-hunk
   nitpick-test--hunk '(10 3) '(10 4)
   (lambda (section)
     (should (equal (mapcar #'cdr (nitpick--hunk-body section))
                    '((?\s 10 10) (?- nil 11) (?+ 11 nil) (?+ 12 nil)
                      (?\s 13 12)))))))

(ert-deftest nitpick-test-hunk-body-skips-the-no-newline-marker ()
  "`\\ No newline at end of file' belongs to neither side, so it counts on neither."
  (nitpick-test--in-hunk
   (concat "+added\n\\ No newline at end of file\n+last\n") '(10 0) '(10 2)
   (lambda (section)
     (should (equal (mapcar (lambda (l) (nth 2 l)) (nitpick--hunk-body section))
                    '(10 11))))))

(ert-deftest nitpick-test-hunk-selection-spans-the-added-lines ()
  "The whole hunk, with no region: the additions, not the context around them."
  (nitpick-test--in-hunk
   nitpick-test--hunk '(10 3) '(10 4)
   (lambda (section)
     (should (equal (nitpick--hunk-selection section nil nil) '("RIGHT" 11 12))))))

(ert-deftest nitpick-test-hunk-selection-of-a-removal-is-the-base-side ()
  (nitpick-test--in-hunk
   (concat " keep\n-gone\n-also gone\n") '(10 3) '(10 1)
   (lambda (section)
     (should (equal (nitpick--hunk-selection section nil nil) '("LEFT" 11 12))))))

(ert-deftest nitpick-test-hunk-selection-of-context-only-is-the-pr-side ()
  "A selection with nothing changed in it still has lines the forge knows."
  (nitpick-test--in-hunk
   nitpick-test--hunk '(10 3) '(10 4)
   (lambda (section)
     (let ((beg (point-min))
           (end (save-excursion (goto-char (point-min)) (line-end-position))))
       (should (equal (nitpick--hunk-selection section beg end) '("RIGHT" 10 10)))))))

(ert-deftest nitpick-test-hunk-selection-narrows-to-the-region ()
  (nitpick-test--in-hunk
   nitpick-test--hunk '(10 3) '(10 4)
   (lambda (section)
     (let ((beg (save-excursion (goto-char (point-min)) (forward-line 3) (point)))
           (end (save-excursion (goto-char (point-min)) (forward-line 4) (point))))
       ;; the second addition only: an end at the beginning of a line stops
       ;; before it
       (should (equal (nitpick--hunk-selection section beg end) '("RIGHT" 12 12)))))))

(ert-deftest nitpick-test-hunk-target-carries-the-path-and-the-side ()
  (nitpick-test--in-hunk
   nitpick-test--hunk '(10 3) '(10 4)
   (lambda (section)
     (nitpick-test--with-stubs
         ((magit-toplevel (lambda (&rest _) "/repo"))
          (magit-git-success (lambda (&rest _) t)))
       (let ((target (nitpick--hunk-target section nil nil)))
         (should (equal (alist-get 'path target) "src/thing.el"))
         (should (equal (alist-get 'side target) "RIGHT"))
         (should (equal (alist-get 'start-line target) 11))
         (should (equal (alist-get 'line target) 12)))))))

(ert-deftest nitpick-test-hunk-target-collapses-a-single-line-hunk ()
  (nitpick-test--in-hunk
   "+added\n" '(10 0) '(10 1)
   (lambda (section)
     (nitpick-test--with-stubs
         ((magit-toplevel (lambda (&rest _) "/repo"))
          (magit-git-success (lambda (&rest _) t)))
       (let ((target (nitpick--hunk-target section nil nil)))
         (should (equal (alist-get 'line target) 10))
         (should-not (alist-get 'start-line target)))))))

(ert-deftest nitpick-test-hunk-target-refuses-an-uncommitted-file ()
  "The new side of the diff is the worktree; dirty, its lines are not the PR's."
  (nitpick-test--in-hunk
   nitpick-test--hunk '(10 3) '(10 4)
   (lambda (section)
     (nitpick-test--with-stubs
         ((magit-toplevel (lambda (&rest _) "/repo"))
          (magit-git-success (lambda (&rest _) nil)))
       (should-error (nitpick--hunk-target section nil nil) :type 'user-error)))))

(ert-deftest nitpick-test-hunk-target-refuses-a-combined-diff ()
  (nitpick-test--in-hunk
   nitpick-test--hunk '((10 3) (10 3)) '(10 4)
   (lambda (section)
     (should-error (nitpick--hunk-target section nil nil) :type 'user-error))
   t))

(ert-deftest nitpick-test-hunk-at-point-ignores-the-status-buffer ()
  "A magit status hunk is the worktree's, so it is not a target."
  (nitpick-test--with-stubs ((magit-current-section (lambda () '((type . hunk)))))
    (with-temp-buffer
      (should-not (nitpick--diff-hunk-at-point)))))

(ert-deftest nitpick-test-comment-in-a-diff-buffer-needs-a-hunk ()
  "Point on a file heading is in the diff but on no line of it."
  (nitpick-test--with-stubs
      ((nitpick--gh (lambda () "/bin/true"))
       (nitpick--diff-buffer-p (lambda () t))
       (nitpick--diff-hunk-at-point (lambda () nil)))
    (with-temp-buffer
      (should-error (nitpick-comment) :type 'user-error))))

(ert-deftest nitpick-test-comment-targets-the-hunk-at-point ()
  (nitpick-test--in-hunk
   nitpick-test--hunk '(10 3) '(10 4)
   (lambda (section)
     (nitpick-test--with-stubs
         ((nitpick--gh (lambda () "/bin/true"))
          (nitpick--diff-hunk-at-point (lambda () section))
          (magit-toplevel (lambda (&rest _) "/repo"))
          (magit-git-success (lambda (&rest _) t))
          (pop-to-buffer (lambda (&rest _) nil)))
       (nitpick-comment)
       (with-current-buffer "*nitpick-comment*"
         (should (equal (alist-get 'path nitpick--comment-ctx) "src/thing.el"))
         (should (equal (alist-get 'side nitpick--comment-ctx) "RIGHT"))
         (should (equal (alist-get 'start-line nitpick--comment-ctx) 11))
         (should (equal (alist-get 'line nitpick--comment-ctx) 12)))))))

(ert-deftest nitpick-test-comment-add-sends-the-targets-side ()
  (let* ((rec (nitpick-test--recorder '((node . nil))))
         (cell (car rec)))
    (nitpick-test--with-stubs
        ((nitpick--graphql (cdr rec))
         (nitpick--pr-ctx (lambda (&rest _) '((id . "PR_1") (number . 7)
                                              (head . "deadbeef"))))
         (nitpick--ensure-review (lambda (&rest _) "PRR_1"))
         (shell-command-to-string (lambda (&rest _) "deadbeef\n"))
         (quit-window (lambda (&rest _) nil)))
      (with-temp-buffer
        (setq nitpick--comment-ctx
              (list (cons 'root default-directory) (cons 'path "src/thing.el")
                    (cons 'line 12) (cons 'start-line 11) (cons 'side "LEFT")))
        (insert "on the base side")
        (nitpick--comment-add))
      (should (equal (alist-get 'd (cdr cell)) "LEFT"))
      (should (equal (alist-get 's (cdr cell)) 11)))))

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

;;;; Changed-file tree: closing it again

(ert-deftest nitpick-test-tree-unpaint-turns-off-what-the-pane-turned-on ()
  "Closing undoes the pane's own painting."
  (let ((nitpick-tree--painted t)
        (called nil))
    (nitpick-test--with-stubs
        ((nitpick-diff-hl-line-mode (lambda (&rest args) (setq called args))))
      (nitpick-tree--unpaint)
      (should (equal called '(-1)))
      (should-not nitpick-tree--painted))))

(ert-deftest nitpick-test-tree-unpaint-leaves-the-users-own-painting-alone ()
  "A mode turned on with the command for it is not the pane's to turn off."
  (let ((nitpick-tree--painted nil)
        (called nil))
    (nitpick-test--with-stubs
        ((nitpick-diff-hl-line-mode (lambda (&rest args) (setq called args))))
      (nitpick-tree--unpaint)
      (should-not called))))

(ert-deftest nitpick-test-tree-close-takes-the-buffer-with-the-window ()
  "It holds a diff read once; opening again reads a fresh one."
  (let ((nitpick-tree-buffer-name "*nitpick-test-pane*")
        (nitpick-tree--painted nil))
    (get-buffer-create nitpick-tree-buffer-name)
    (save-window-excursion
      (delete-other-windows)
      (set-window-buffer (split-window) nitpick-tree-buffer-name)
      (should (nitpick-tree--window))
      (nitpick-tree-close)
      (should-not (get-buffer nitpick-tree-buffer-name)))))

(ert-deftest nitpick-test-tree-close-is-fine-with-no-pane-at-all ()
  "Nothing open is not an error, so the key is safe to lean on."
  (let ((nitpick-tree-buffer-name "*nitpick-test-absent-pane*")
        (nitpick-tree--painted nil))
    (should-not (nitpick-tree-close))))

(ert-deftest nitpick-test-tree-closes-when-called-with-no-revision ()
  "The interactive form answers (nil nil) for a pane that is already open."
  (let ((closed nil)
        (opened nil))
    (nitpick-test--with-stubs
        ((nitpick-tree-close (lambda () (setq closed t)))
         (nitpick-tree--open (lambda (&rest args) (setq opened args))))
      (nitpick-tree nil nil)
      (should closed)
      (should-not opened))))

(ert-deftest nitpick-test-tree-opens-when-given-a-revision ()
  "And renders rather than closing when it was handed something to show."
  (let ((closed nil)
        (opened nil))
    (nitpick-test--with-stubs
        ((nitpick-tree-close (lambda () (setq closed t)))
         (nitpick-tree--open (lambda (&rest args) (setq opened args))))
      (nitpick-tree "/tmp/wt" "master...")
      (should (equal opened '("/tmp/wt" "master..." nil)))
      (should-not closed))))

(ert-deftest nitpick-test-tree-pane-binds-q-to-its-own-close ()
  "`treemacs-quit' buries the pane and leaves the painting on."
  (should (eq (lookup-key nitpick-tree-mode-map "q") #'nitpick-tree-close)))

;;;; Diffing the file being visited

(ert-deftest nitpick-test-diff-show-passes-only-the-args-half ()
  "`magit-diff-arguments' answers (ARGS FILES); its FILES is the last diff's."
  (let (sent)
    (nitpick-test--with-stubs
        ((magit-diff-arguments (lambda (&rest _) '(("--stat") ("stale.el"))))
         (magit-diff-range (lambda (rev args files) (setq sent (list rev args files)))))
      (nitpick-diff-show "abc123" '("a.el"))
      (should (equal sent '("abc123" ("--stat") ("a.el")))))))

(ert-deftest nitpick-test-diff-buffer-file-diffs-the-visited-file ()
  "The revision this worktree picked, limited to the file in the buffer."
  (let (sent)
    (nitpick-test--with-stubs
        ((magit-toplevel (lambda (&rest _) "/tmp/wt"))
         (magit-file-relative-name (lambda (&rest _) "src/a.el"))
         (nitpick-diff-hl--suggested-base (lambda (&rest _) "master"))
         (magit-diff-arguments (lambda (&rest _) '(nil nil)))
         (magit-diff-range (lambda (rev _args files) (setq sent (list rev files)))))
      (nitpick-diff-buffer-file)
      (should (equal sent '("master" ("src/a.el")))))))

(ert-deftest nitpick-test-diff-buffer-file-resolves-a-merge-base ()
  "A trailing `...' is the merge base here too, as everywhere in nitpick."
  (let (sent)
    (nitpick-test--with-stubs
        ((magit-toplevel (lambda (&rest _) "/tmp/wt"))
         (magit-file-relative-name (lambda (&rest _) "a.el"))
         (nitpick-diff-hl--suggested-base (lambda (&rest _) "master..."))
         (magit-git-string (lambda (&rest args)
                             (and (equal (car args) "merge-base") "abc123")))
         (magit-diff-arguments (lambda (&rest _) '(nil nil)))
         (magit-diff-range (lambda (rev _args _files) (setq sent rev))))
      (nitpick-diff-buffer-file)
      (should (equal sent "abc123")))))

(ert-deftest nitpick-test-diff-buffer-file-refuses-a-buffer-with-no-file ()
  "Nothing to limit the diff to, so say so rather than diffing everything."
  (nitpick-test--with-stubs
      ((magit-toplevel (lambda (&rest _) "/tmp/wt"))
       (magit-file-relative-name (lambda (&rest _) nil))
       (magit-diff-range (lambda (&rest _) (error "should not be called"))))
    (should-error (nitpick-diff-buffer-file) :type 'user-error)))

(ert-deftest nitpick-test-diff-buffer-file-refuses-outside-a-repository ()
  "No repository, no base, no diff."
  (nitpick-test--with-stubs
      ((magit-toplevel (lambda (&rest _) nil))
       (magit-diff-range (lambda (&rest _) (error "should not be called"))))
    (should-error (nitpick-diff-buffer-file) :type 'user-error)))

(ert-deftest nitpick-test-prefix-map-binds-d-to-the-file-diff ()
  "`d' is the file's diff wherever it is pressed: the pane, or the file."
  (should (eq (lookup-key nitpick-prefix-map "d") #'nitpick-diff-buffer-file)))

;;;; Changed-file tree: the diff beside the pane

(defun nitpick-test--section (type value &optional start children end)
  "Return a stand-in for a magit section of TYPE holding VALUE.
A plist read through the stubbed `nitpick--oref' below: magit's classes are
not here to instantiate, and every slot the pane reads goes through that one
accessor.  START and END are the section's span, CHILDREN the sections under
it."
  (list :type type :value value :start (or start 1) :children children
        :end end))

(defun nitpick-test--oref-stub ()
  "Return a `nitpick--oref' stub reading `nitpick-test--section' plists."
  (lambda (object slot)
    (plist-get object (intern (concat ":" (symbol-name slot))))))

(defmacro nitpick-test--with-diff (sections &rest body)
  "Run BODY with `buffer' bound to a diff buffer whose root holds SECTIONS."
  (declare (indent 1))
  `(let ((buffer (generate-new-buffer " *nitpick-test-diff*")))
     (unwind-protect
         (nitpick-test--with-stubs ((nitpick--oref (nitpick-test--oref-stub)))
           (with-current-buffer buffer
             (setq-local magit-root-section
                         (nitpick-test--section 'diffbuf nil 1 ,sections)))
           ,@body)
       (kill-buffer buffer))))

(defun nitpick-test--starts (sections)
  "Return the positions SECTIONS start at."
  (mapcar (lambda (section) (plist-get section :start)) sections))

(defun nitpick-test--sections-of (buffer node)
  "Return the sections of BUFFER's diff that NODE covers."
  (nitpick-tree--node-sections
   (nitpick-tree--file-sections buffer) node "/tmp/wt"))

(ert-deftest nitpick-test-tree-sections-of-a-file-are-the-one-named-by-it ()
  "A file is revealed through the section git wrote for it, and no other."
  (nitpick-test--with-diff
      (list (nitpick-test--section 'file "src/a.el" 10)
            (nitpick-test--section 'file "src/b.el" 20))
    (should (equal (nitpick-test--starts
                    (nitpick-test--sections-of buffer '(:file "src/b.el")))
                   '(20)))))

(ert-deftest nitpick-test-tree-sections-of-a-directory-are-its-whole-subtree ()
  "What the diff is narrowed to: the subtree alone, in the order git wrote it."
  (nitpick-test--with-diff
      (list (nitpick-test--section 'file "docs/x.md" 10)
            (nitpick-test--section 'file "src/a.el" 20)
            (nitpick-test--section 'file "src/sub/c.el" 30)
            (nitpick-test--section 'file "src/b.el" 40))
    (should (equal (nitpick-test--starts
                    (nitpick-test--sections-of
                     buffer '(:dir t :path "/tmp/wt/src")))
                   '(20 30 40)))))

(ert-deftest nitpick-test-tree-sections-of-a-directory-match-whole-names ()
  "`src' is not the directory of `srcfoo/a.el': the prefix ends in a slash."
  (nitpick-test--with-diff
      (list (nitpick-test--section 'file "srcfoo/a.el" 10))
    (should-not (nitpick-test--sections-of
                 buffer '(:dir t :path "/tmp/wt/src")))))

(ert-deftest nitpick-test-tree-sections-ignore-anything-but-a-file ()
  "The diffstat names the same files; its sections are not where they start."
  (nitpick-test--with-diff
      (list (nitpick-test--section 'diffstat "src/a.el" 5)
            (nitpick-test--section 'file "src/a.el" 40))
    (should (equal (nitpick-test--starts
                    (nitpick-test--sections-of buffer '(:file "src/a.el")))
                   '(40)))))

(ert-deftest nitpick-test-tree-sections-of-a-file-not-in-the-diff-are-none ()
  "A pane read before the last commit lists files the diff no longer has."
  (nitpick-test--with-diff
      (list (nitpick-test--section 'file "src/a.el" 10))
    (should-not (nitpick-test--sections-of buffer '(:file "src/gone.el")))))

(ert-deftest nitpick-test-tree-sections-of-a-subtree-are-one-run ()
  "Which is what narrowing needs: git orders a diff by path."
  (nitpick-test--with-diff
      (list (nitpick-test--section 'file "docs/x.md" 10)
            (nitpick-test--section 'file "src/a.el" 20)
            (nitpick-test--section 'file "src/b.el" 30))
    (let ((node '(:dir t :path "/tmp/wt/src")))
      (should (nitpick-tree--contiguous-p
               (nitpick-tree--file-sections buffer)
               (nitpick-test--sections-of buffer node))))))

(ert-deftest nitpick-test-tree-sections-split-by-a-foreign-file-are-not ()
  "Rename detection can place a file outside its own directory's run, and
Emacs cannot narrow around the hole that leaves."
  (nitpick-test--with-diff
      (list (nitpick-test--section 'file "src/a.el" 10)
            (nitpick-test--section 'file "docs/x.md" 20)
            (nitpick-test--section 'file "src/b.el" 30))
    (let ((node '(:dir t :path "/tmp/wt/src")))
      (should-not (nitpick-tree--contiguous-p
                   (nitpick-tree--file-sections buffer)
                   (nitpick-test--sections-of buffer node))))))

(ert-deftest nitpick-test-tree-build-diff-asks-for-the-whole-range ()
  "One `git diff' per review, not one per file: no pathspec at all.
The user's diff arguments are kept; the pathspec magit answers with - its
last diff's - is dropped, the way `nitpick-diff-show' drops it."
  (let ((sent nil)
        (noselect nil))
    (nitpick-test--with-stubs
        ((magit-diff-arguments (lambda (&rest _) '(("--stat") ("stale.el"))))
         (magit-diff-range
          (lambda (rev args files)
            (setq sent (list rev args files)
                  noselect magit-display-buffer-noselect)
            (current-buffer))))
      (nitpick-tree--build-diff "/tmp/wt" "origin/master")
      (should (equal sent '("origin/master" ("--stat") nil)))
      ;; The pane keeps the point: magit would select the diff it displays.
      (should noselect))))

(ert-deftest nitpick-test-tree-build-diff-resolves-a-merge-base-revision ()
  "A trailing `...' is the merge base here too, as everywhere in nitpick."
  (let ((sent nil))
    (nitpick-test--with-stubs
        ((magit-diff-arguments (lambda (&rest _) '(nil nil)))
         (magit-git-string (lambda (&rest args)
                             (and (equal (car args) "merge-base") "abc123")))
         (magit-diff-range (lambda (rev &rest _)
                             (setq sent rev)
                             (current-buffer))))
      (nitpick-tree--build-diff "/tmp/wt" "origin/master...")
      (should (equal sent "abc123")))))

(ert-deftest nitpick-test-tree-build-diff-remembers-the-buffer-it-read ()
  "Which is what the next reveal scrolls instead of reading the range again."
  (let ((nitpick-tree--diff-buffer nil))
    (nitpick-test--with-windows (diff)
      (nitpick-test--with-stubs
          ((magit-diff-arguments (lambda (&rest _) '(nil nil)))
           (magit-diff-range (lambda (&rest _) diff)))
        (should (eq (nitpick-tree--build-diff "/tmp/wt" "master") diff))
        (should (eq nitpick-tree--diff-buffer diff))
        ;; And is not read a second time.
        (nitpick-test--with-stubs
            ((magit-diff-range (lambda (&rest _) (error "already read"))))
          (should (eq (nitpick-tree--ensure-diff "/tmp/wt" "master") diff)))))))

(ert-deftest nitpick-test-tree-build-diff-insists-on-a-buffer ()
  "Everything downstream scrolls that buffer; nil would fail line by line."
  (let ((nitpick-tree--diff-buffer nil))
    (nitpick-test--with-stubs
        ((magit-diff-arguments (lambda (&rest _) '(nil nil)))
         (magit-diff-range (lambda (&rest _) nil)))
      (should-error (nitpick-tree--build-diff "/tmp/wt" "master")))))

(ert-deftest nitpick-test-tree-main-window-passes-over-a-side-window ()
  "The pane lives in one, and a side window shows nothing but the pane."
  (nitpick-test--with-windows (side main)
    (set-window-buffer (selected-window) main)
    (display-buffer-in-side-window side '((side . left) (slot . 1)))
    (should (eq (nitpick-tree--main-window) (get-buffer-window main)))))

(ert-deftest nitpick-test-tree-diff-is-on-screen-only-when-a-window-shows-it ()
  "A refresh re-reads the range only when it would land where it already is."
  (nitpick-test--with-windows (other diff)
    (let ((nitpick-tree--diff-buffer diff))
      (set-window-buffer (selected-window) other)
      (should-not (nitpick-tree--diff-on-screen-p))
      (set-window-buffer (selected-window) diff)
      (should (nitpick-tree--diff-on-screen-p)))))

(ert-deftest nitpick-test-tree-reveal-shows-the-section-and-puts-it-on-top ()
  "Expanded first: magit draws a deleted file collapsed, and that is a file
a review has to read."
  (let ((shown nil))
    (nitpick-test--with-windows (pane diff)
      (with-current-buffer diff
        (insert (make-string 400 ?\n)))
      (set-window-buffer (selected-window) diff)
      (with-current-buffer pane
        (setq-local nitpick-tree--root "/tmp/wt"
                    nitpick-tree--revision "master")
        (nitpick-test--with-stubs
            ((nitpick--oref (nitpick-test--oref-stub))
             (magit-section-show (lambda (section) (setq shown section)))
             (nitpick-tree--ensure-diff (lambda (&rest _) diff))
             (nitpick-tree--file-sections (lambda (&rest _) nil))
             (nitpick-tree--node-sections
              (lambda (&rest _)
                (list (nitpick-test--section 'file "a.el" 120)))))
          (let ((nitpick-tree-narrow nil))
            (should (nitpick-tree--reveal '(:file "a.el" :status "M"))))
          (should (equal (plist-get shown :value) "a.el"))
          (should (= (with-current-buffer diff (point)) 120))
          (should (= (window-start (get-buffer-window diff)) 120)))))))

(ert-deftest nitpick-test-tree-reveal-keeps-the-point-unless-asked ()
  "Following the point must not take it: the pane is still being navigated."
  (nitpick-test--with-windows (pane diff)
    (let ((pane-window (selected-window))
          (diff-window (split-window)))
      (set-window-buffer pane-window pane)
      (set-window-buffer diff-window diff)
      (with-current-buffer pane
        (setq-local nitpick-tree--root "/tmp/wt"
                    nitpick-tree--revision "master")
        (nitpick-test--with-stubs
            ((nitpick--oref (nitpick-test--oref-stub))
             (magit-section-show #'ignore)
             (nitpick-tree--ensure-diff (lambda (&rest _) diff))
             (nitpick-tree--file-sections (lambda (&rest _) nil))
             (nitpick-tree--node-sections
              (lambda (&rest _)
                (list (nitpick-test--section 'file "a.el" 1 nil 1)))))
          (nitpick-tree--reveal '(:file "a.el" :status "M"))
          (should (eq (selected-window) pane-window))
          (nitpick-tree--reveal '(:file "a.el" :status "M") :select)
          (should (eq (selected-window) diff-window)))))))

(ert-deftest nitpick-test-tree-reveal-says-so-when-the-diff-has-no-section ()
  "Silence would read as a diff that has not moved."
  (let ((said nil))
    (nitpick-test--with-windows (pane diff)
      (set-window-buffer (selected-window) diff)
      (with-current-buffer pane
        (setq-local nitpick-tree--root "/tmp/wt"
                    nitpick-tree--revision "master")
        (nitpick-test--with-stubs
            ((nitpick-tree--ensure-diff (lambda (&rest _) diff))
             (nitpick-tree--file-sections (lambda (&rest _) nil))
             (nitpick-tree--node-sections (lambda (&rest _) nil))
             (message (lambda (fmt &rest args)
                        (setq said (apply #'format fmt args)))))
          (nitpick-tree--reveal '(:file "gone.el" :status "M"))
          (should (string-match-p "gone.el" said)))))))

(defun nitpick-test--reveal-span (sections node narrow)
  "Reveal NODE over SECTIONS, narrowing when NARROW.
Returns what the diff window then shows, as (POINT-MIN POINT-MAX POINT) in a
buffer of 300 characters."
  (let ((span nil))
    (nitpick-test--with-windows (pane diff)
      (with-current-buffer diff
        (insert (make-string 300 ?x))
        (setq-local magit-root-section
                    (nitpick-test--section 'diffbuf nil 1 sections)))
      (set-window-buffer (selected-window) diff)
      (with-current-buffer pane
        (setq-local nitpick-tree--root "/tmp/wt"
                    nitpick-tree--revision "master")
        (nitpick-test--with-stubs
            ((nitpick--oref (nitpick-test--oref-stub))
             (magit-section-show #'ignore)
             (nitpick-tree--ensure-diff (lambda (&rest _) diff)))
          (let ((nitpick-tree-narrow narrow))
            (nitpick-tree--reveal node))))
      (with-current-buffer diff
        (setq span (list (point-min) (point-max) (point)))))
    span))

(defconst nitpick-test--spans
  (list (nitpick-test--section 'file "src/a.el" 10 nil 100)
        (nitpick-test--section 'file "src/b.el" 100 nil 200)
        (nitpick-test--section 'file "docs/x.md" 200 nil 300))
  "Three file sections of a 300-character diff, in the order git wrote them.")

(ert-deftest nitpick-test-tree-reveal-narrows-a-directory-to-its-subtree ()
  "The point of it: a file outside the subtree is not on screen to read."
  (should (equal (nitpick-test--reveal-span
                  nitpick-test--spans '(:dir t :path "/tmp/wt/src") t)
                 '(10 200 10))))

(ert-deftest nitpick-test-tree-reveal-narrows-a-file-to-its-own-diff ()
  "A leaf narrows too: the diff of that file, not the range it sits in."
  (should (equal (nitpick-test--reveal-span
                  nitpick-test--spans '(:file "src/b.el" :status "M") t)
                 '(100 200 100))))

(ert-deftest nitpick-test-tree-reveal-keeps-the-whole-range-when-widened ()
  "`N' off is the continuous diff: the file before and after a scroll away."
  (should (equal (nitpick-test--reveal-span
                  nitpick-test--spans '(:file "src/b.el" :status "M") nil)
                 '(1 301 100))))

(ert-deftest nitpick-test-tree-reveal-scrolls-to-a-subtree-git-split ()
  "Emacs narrows to one region, and the hole would hide a file to read."
  (should (equal (nitpick-test--reveal-span
                  (list (nitpick-test--section 'file "src/a.el" 10 nil 100)
                        (nitpick-test--section 'file "docs/x.md" 100 nil 200)
                        (nitpick-test--section 'file "src/b.el" 200 nil 300))
                  '(:dir t :path "/tmp/wt/src") t)
                 '(1 301 10))))

(ert-deftest nitpick-test-tree-widen-gives-the-whole-range-back ()
  "What `N' and closing the pane do, so no narrowed diff is left behind."
  (let ((buffer (generate-new-buffer " *nitpick-test-diff*")))
    (unwind-protect
        (let ((nitpick-tree--diff-buffer buffer))
          (with-current-buffer buffer
            (insert (make-string 300 ?x))
            (narrow-to-region 10 20))
          (nitpick-tree--widen)
          (with-current-buffer buffer
            (should (= (point-min) 1))
            (should (= (point-max) 301))))
      (kill-buffer buffer))))

(ert-deftest nitpick-test-tree-toggle-narrow-widens-and-reveals-again ()
  "Widened first: the node is revealed into a diff that holds its range."
  (let ((revealed nil)
        (buffer (generate-new-buffer " *nitpick-test-diff*")))
    (unwind-protect
        (let ((nitpick-tree--diff-buffer buffer)
              (nitpick-tree-narrow t))
          (with-current-buffer buffer
            (insert (make-string 300 ?x))
            (narrow-to-region 10 20))
          (nitpick-test--with-stubs
              ((nitpick-tree--follow
                (lambda ()
                  (setq revealed (with-current-buffer buffer
                                   (list (point-min) (point-max)))))))
            (nitpick-tree-toggle-narrow))
          (should-not nitpick-tree-narrow)
          (should (equal revealed '(1 301))))
      (kill-buffer buffer))))

(ert-deftest nitpick-test-tree-reveal-of-an-untracked-file-diffs-it-alone ()
  "git holds no version of it, so it is in no range diff - show it anyway."
  (let ((args nil))
    (unwind-protect
        (nitpick-test--with-windows (pane other)
          (set-window-buffer (selected-window) other)
          (with-current-buffer pane
            (setq-local nitpick-tree--root "/tmp/wt"
                        nitpick-tree--revision "master")
            (nitpick-test--with-stubs
                ((nitpick-tree--git-output
                  (lambda (&rest called) (setq args called) "+added\n"))
                 (nitpick-tree--ensure-diff
                  (lambda (&rest _) (error "the range diff has no untracked file"))))
              (should (nitpick-tree--reveal '(:file "new.el" :status "?")))
              (should (equal args '("diff" "--no-index" "--"
                                    "/dev/null" "new.el")))
              (with-current-buffer nitpick-tree-untracked-buffer-name
                (should (derived-mode-p 'diff-mode))
                (should (equal default-directory "/tmp/wt"))
                (should (string-match-p "added" (buffer-string)))))))
      (let ((buffer (get-buffer nitpick-tree-untracked-buffer-name)))
        (when buffer (kill-buffer buffer))))))

(ert-deftest nitpick-test-tree-untracked-diff-says-an-empty-file-is-empty ()
  "`--no-index' prints nothing at all for a file with no lines in it."
  (unwind-protect
      (nitpick-test--with-stubs
          ((nitpick-tree--git-output (lambda (&rest _) "")))
        (with-current-buffer (nitpick-tree--untracked-diff "new.el" "/tmp/wt")
          (should (string-match-p "new.el is empty" (buffer-string)))))
    (let ((buffer (get-buffer nitpick-tree-untracked-buffer-name)))
      (when buffer (kill-buffer buffer)))))

(ert-deftest nitpick-test-tree-follow-reveals-a-node-once ()
  "Several commands run per keystroke, and one of them moved the point."
  (let ((revealed nil))
    (with-temp-buffer
      (nitpick-test--with-stubs
          ((nitpick-tree--node-at-point
            (lambda () '(:file "a.el" :path "/tmp/wt/a.el")))
           (nitpick-tree--reveal (lambda (node &optional _) (push node revealed))))
        (nitpick-tree--follow)
        (nitpick-tree--follow)
        (should (= (length revealed) 1))))))

(ert-deftest nitpick-test-tree-follow-reveals-the-next-node ()
  (let ((nodes '((:file "a.el" :path "/tmp/wt/a.el")
                 (:file "b.el" :path "/tmp/wt/b.el")))
        (revealed nil))
    (with-temp-buffer
      (nitpick-test--with-stubs
          ((nitpick-tree--node-at-point (lambda () (pop nodes)))
           (nitpick-tree--reveal (lambda (node &optional _) (push node revealed))))
        (nitpick-tree--follow)
        (nitpick-tree--follow)
        (should (= (length revealed) 2))))))

(ert-deftest nitpick-test-tree-follow-obeys-its-option ()
  "Off, the pane is a list of files again."
  (let ((nitpick-tree-follow nil)
        (revealed nil))
    (with-temp-buffer
      (nitpick-test--with-stubs
          ((nitpick-tree--node-at-point (lambda () '(:file "a.el" :path "/a.el")))
           (nitpick-tree--reveal (lambda (&rest _) (setq revealed t))))
        (nitpick-tree--follow)
        (should-not revealed)))))

(ert-deftest nitpick-test-tree-follow-swallows-a-user-error ()
  "It runs on every keystroke in the pane: a refusal must not break them all."
  (with-temp-buffer
    (nitpick-test--with-stubs
        ((nitpick-tree--node-at-point (lambda () '(:file "a.el" :path "/a.el")))
         (nitpick-tree--reveal (lambda (&rest _) (user-error "No diff"))))
      (should-not (nitpick-tree--follow)))))

(ert-deftest nitpick-test-tree-follow-lets-a-real-error-through ()
  "Only a refusal is swallowed; a bug in the reveal is still a bug."
  (with-temp-buffer
    (nitpick-test--with-stubs
        ((nitpick-tree--node-at-point (lambda () '(:file "a.el" :path "/a.el")))
         (nitpick-tree--reveal (lambda (&rest _) (error "Boom"))))
      (should-error (nitpick-tree--follow) :type 'error))))

(ert-deftest nitpick-test-tree-toggle-follow-reveals-what-it-skipped ()
  "Turned on with the point already on a file, that file is what to show."
  (let ((nitpick-tree-follow nil)
        (revealed nil))
    (with-temp-buffer
      (nitpick-test--with-stubs
          ((nitpick-tree--node-at-point (lambda () '(:file "a.el" :path "/a.el")))
           (nitpick-tree--reveal (lambda (&rest _) (setq revealed t)))
           (message #'ignore))
        (nitpick-tree-toggle-follow)
        (should nitpick-tree-follow)
        (should revealed)
        (nitpick-tree-toggle-follow)
        (should-not nitpick-tree-follow)))))

(ert-deftest nitpick-test-tree-visit-diff-hands-the-point-to-the-diff ()
  "`d' is how a diff is asked for when nothing is following the point."
  (let ((select 'unset))
    (with-temp-buffer
      (nitpick-test--with-stubs
          ((nitpick-tree--node-at-point
            (lambda () '(:file "a.el" :path "/tmp/wt/a.el")))
           (nitpick-tree--reveal (lambda (_node &optional arg) (setq select arg))))
        (nitpick-tree-visit-diff)
        (should select)
        ;; And is not revealed again by the hook on the way out.
        (should (equal nitpick-tree--followed "/tmp/wt/a.el"))
        (nitpick-tree-visit-diff :stay)
        (should-not select)))))

(ert-deftest nitpick-test-tree-ret-steps-into-the-diff-of-a-file ()
  "The pane navigates; the diff is where a hunk is read and commented on."
  (let ((stepped nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--node-at-point (lambda () '(:file "a.el")))
         (nitpick-tree-visit-diff (lambda (&rest _) (setq stepped t)))
         (nitpick-tree-visit (lambda (&rest _) (error "`o' opens the file"))))
      (nitpick-tree-ret)
      (should stepped))))

(ert-deftest nitpick-test-tree-ret-folds-a-directory ()
  "As everywhere in treemacs: RET on a directory is not a diff."
  (let ((folded nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--node-at-point (lambda () '(:dir t :name "src")))
         (nitpick-tree-visit (lambda (&rest _) (setq folded t)))
         (nitpick-tree-visit-diff (lambda (&rest _) (error "not a file"))))
      (nitpick-tree-ret)
      (should folded))))

(ert-deftest nitpick-test-tree-pane-binds-d-to-the-diff ()
  "`d' is diff in the pane, not `treemacs-delete-file'."
  (should (eq (lookup-key nitpick-tree-mode-map "d") #'nitpick-tree-visit-diff)))

(ert-deftest nitpick-test-tree-pane-refreshes-by-re-reading-the-diff ()
  "`treemacs-refresh' would redraw the same nodes and claim success."
  (should (eq (lookup-key nitpick-tree-mode-map "r") #'nitpick-tree-refresh))
  (should (eq (lookup-key nitpick-tree-mode-map "g") #'nitpick-tree-refresh)))

(ert-deftest nitpick-test-tree-pane-binds-o-to-the-file-itself ()
  "treemacs' own `o' opens a node in a split, which a review has no use for."
  (should (eq (lookup-key nitpick-tree-mode-map "o") #'nitpick-tree-visit)))

(ert-deftest nitpick-test-tree-pane-binds-f-to-the-follow-toggle ()
  (should (eq (lookup-key nitpick-tree-mode-map "f")
              #'nitpick-tree-toggle-follow)))

(ert-deftest nitpick-test-tree-takes-the-frame-and-gives-it-back ()
  "A review is a mode of its own; the layout it replaced is not lost."
  (nitpick-test--with-windows (one two)
    (let ((nitpick-tree--window-config nil))
      (set-window-buffer (selected-window) one)
      (set-window-buffer (split-window) two)
      (nitpick-test--with-stubs ((nitpick-tree--window (lambda () nil)))
        (nitpick-tree--take-frame))
      (should (= (length (window-list)) 1))
      (should nitpick-tree--window-config)
      (nitpick-tree--give-frame-back)
      (should (= (length (window-list)) 2))
      (should-not nitpick-tree--window-config))))

(ert-deftest nitpick-test-tree-takes-the-frame-once ()
  "The layout to give back is the one from before the review, not its own."
  (nitpick-test--with-windows (pane)
    (let ((nitpick-tree--window-config 'saved))
      (nitpick-test--with-stubs
          ((nitpick-tree--window (lambda () (selected-window))))
        (nitpick-tree--take-frame))
      (should (eq nitpick-tree--window-config 'saved)))))

(ert-deftest nitpick-test-tree-leaves-the-frame-alone-when-told-to ()
  (nitpick-test--with-windows (one two)
    (let ((nitpick-tree-full-frame nil)
          (nitpick-tree--window-config nil))
      (set-window-buffer (selected-window) one)
      (set-window-buffer (split-window) two)
      (nitpick-test--with-stubs ((nitpick-tree--window (lambda () nil)))
        (nitpick-tree--take-frame))
      (should (= (length (window-list)) 2))
      (should-not nitpick-tree--window-config))))

(ert-deftest nitpick-test-tree-close-forgets-the-diff-it-navigated ()
  "The buffer stays, the way magit's buffers do; the next review re-reads it."
  (nitpick-test--with-windows (diff)
    (let ((nitpick-tree--diff-buffer diff)
          (nitpick-tree--window-config nil))
      (nitpick-tree-close)
      (should-not nitpick-tree--diff-buffer)
      (should (buffer-live-p diff)))))

;;;; Visiting the base's blob from a diff

;; magit's buffer-locals, which the suite runs without magit to set.
(defvar magit-buffer-diff-type nil)
(defvar magit-buffer-diff-range nil)
(defvar magit-buffer-revision nil)
(defvar treemacs--open-node-states nil)

(defmacro nitpick-test--in-diff (type range &rest body)
  "Run BODY as if in a magit diff buffer of TYPE showing RANGE."
  (declare (indent 2))
  `(nitpick-test--with-stubs
       ((derived-mode-p (lambda (&rest modes) (memq 'magit-diff-mode modes)))
        (magit-rev-verify (lambda (rev) (equal rev "abc123"))))
     (let ((magit-buffer-diff-type ,type)
           (magit-buffer-diff-range ,range))
       ,@body)))

(ert-deftest nitpick-test-visit-sides-names-the-revision-and-the-worktree ()
  "`magit-split-range' answers nil for a bare revision, so magit has no sides."
  (nitpick-test--in-diff 'committed "abc123"
    (should (equal (nitpick--diff-visit-sides '((nil "a.el") (nil "a.el")))
                   '(("abc123" "a.el") ("{worktree}" "a.el"))))))

(ert-deftest nitpick-test-visit-sides-keeps-the-old-name-of-a-rename ()
  "The left side is the file as the revision spelled it."
  (nitpick-test--in-diff 'committed "abc123"
    (should (equal (nitpick--diff-visit-sides '((nil "old.el") (nil "new.el")))
                   '(("abc123" "old.el") ("{worktree}" "new.el"))))))

(ert-deftest nitpick-test-visit-sides-leaves-magits-own-answers-alone ()
  "A commit, a stash, staged, unstaged, a two-dot range: magit has the sides."
  (nitpick-test--in-diff 'committed "abc123"
    (dolist (sides '((("HEAD" "a.el") ("{index}" "a.el"))
                     (("{index}" "a.el") ("{worktree}" "a.el"))
                     (("abc123" "a.el") ("def456" "a.el"))))
      (should (equal (nitpick--diff-visit-sides sides) sides)))))

(ert-deftest nitpick-test-visit-sides-needs-a-committed-diff ()
  "`--no-index' and the unresolved types have no revision to name."
  (nitpick-test--in-diff 'undefined "abc123"
    (should (equal (nitpick--diff-visit-sides '((nil "a.el") (nil "a.el")))
                   '((nil "a.el") (nil "a.el"))))))

(ert-deftest nitpick-test-visit-sides-needs-the-range-to-be-a-revision ()
  "A three-dot range whose merge base cannot be worked out also lands here."
  (nitpick-test--in-diff 'committed "origin/gone..."
    (should (equal (nitpick--diff-visit-sides '((nil "a.el") (nil "a.el")))
                   '((nil "a.el") (nil "a.el"))))))

(ert-deftest nitpick-test-visit-sides-stays-out-of-other-buffers ()
  "The two buffer-locals it reads are magit's; elsewhere they say nothing."
  (nitpick-test--with-stubs
      ((derived-mode-p (lambda (&rest _) nil))
       (magit-rev-verify (lambda (&rest _) t)))
    (let ((magit-buffer-diff-type 'committed)
          (magit-buffer-diff-range "abc123"))
      (should (equal (nitpick--diff-visit-sides '((nil "a.el") (nil "a.el")))
                     '((nil "a.el") (nil "a.el")))))))

(ert-deftest nitpick-test-visit-base-mode-adds-and-removes-its-advice ()
  (nitpick-test--with-stubs
      ((magit-diff-visit--sides (lambda (&rest _) '((nil "a.el") (nil "a.el")))))
    (unwind-protect
        (progn
          (nitpick-diff-visit-base-mode 1)
          (should (advice-member-p #'nitpick--diff-visit-sides
                                   'magit-diff-visit--sides))
          (nitpick-diff-visit-base-mode -1)
          (should-not (advice-member-p #'nitpick--diff-visit-sides
                                       'magit-diff-visit--sides)))
      (nitpick-diff-visit-base-mode -1))))

(ert-deftest nitpick-test-visit-base-mode-is-off-until-enabled ()
  (should-not (advice-member-p #'nitpick--diff-visit-sides
                              'magit-diff-visit--sides)))

;;;; Visiting: which side a line belongs to

(defun nitpick-test--hunk (&rest props)
  "Return a stand-in for a magit hunk section carrying PROPS."
  (append props (list :type 'hunk)))

(defmacro nitpick-test--on-line (text line &rest body)
  "Run BODY with point at the start of LINE of TEXT, in a diff-like buffer.
TEXT is a hunk body; the hunk section stands in for magit's, with `content'
at the first line, so the counting functions walk real text."
  (declare (indent 2))
  `(with-temp-buffer
     (insert ,text)
     (goto-char (point-min))
     (forward-line (1- ,line))
     (let ((nitpick-test--content (point-min)))
       (ignore nitpick-test--content)
       ,@body)))

(defvar nitpick-test--content nil)

(ert-deftest nitpick-test-visit-line-side-of-a-plain-hunk ()
  "A line's own marker says which side it is on; context is on both."
  (let ((hunk (nitpick-test--hunk :combined nil)))
    (nitpick-test--with-stubs
        ((nitpick--oref (nitpick-test--oref-stub))
         (magit-diff--hunk-section (lambda () hunk)))
      (nitpick-test--on-line "+added\n-removed\n context\n" 1
        (should (eq (nitpick--visit-line-side) 'new)))
      (nitpick-test--on-line "+added\n-removed\n context\n" 2
        (should (eq (nitpick--visit-line-side) 'old)))
      (nitpick-test--on-line "+added\n-removed\n context\n" 3
        (should (eq (nitpick--visit-line-side) 'both))))))

(ert-deftest nitpick-test-visit-line-side-outside-a-hunk-is-both ()
  "A file heading belongs to no line, so either side may be opened from it."
  (nitpick-test--with-stubs
      ((magit-diff--hunk-section (lambda () nil)))
    (should (eq (nitpick--visit-line-side) 'both))))

(ert-deftest nitpick-test-visit-line-side-of-a-hunk-heading-is-both ()
  "`@@' is not a line of either side."
  (let ((hunk (nitpick-test--hunk :combined nil)))
    (nitpick-test--with-stubs
        ((nitpick--oref (nitpick-test--oref-stub))
         (magit-diff--hunk-section (lambda () hunk)))
      (nitpick-test--on-line "@@ -1,2 +1,3 @@\n+added\n" 1
        (should (eq (nitpick--visit-line-side) 'both))))))

(defconst nitpick-test--conflict-body
  (concat "  top\n"
          "++<<<<<<< HEAD\n"
          " +OURS\n"
          "++|||||||\n"
          "++shared\n"
          "++=======\n"
          "+ THEIRS\n"
          "++>>>>>>>\n"
          "  bottom\n")
  "The body `git diff' prints for a conflicted file, column for column.")

(defun nitpick-test--conflict-hunk ()
  "Return a stand-in for the hunk of that conflict.
Shaped the way magit builds one: the per-parent ranges in `from-range', the
result's in `to-range', and `from-ranges' - which magit's own line counting
reads - left empty."
  (nitpick-test--hunk :combined t
                      :from-range '((1 3) (1 3))
                      :to-range '(1 9)
                      :content 1))

(ert-deftest nitpick-test-visit-line-side-of-a-combined-hunk ()
  "Each column says what the line is to that parent; a space means it has it."
  (let ((hunk (nitpick-test--conflict-hunk)))
    (nitpick-test--with-stubs
        ((nitpick--oref (nitpick-test--oref-stub))
         (magit-diff--hunk-section (lambda () hunk)))
      (let ((text nitpick-test--conflict-body))
        ;; In both parents.
        (nitpick-test--on-line text 1
          (should (eq (nitpick--visit-line-side) 'both)))
        ;; A marker: in the result and in neither parent.
        (nitpick-test--on-line text 2
          (should (eq (nitpick--visit-line-side) 'new)))
        ;; Ours has it, theirs does not.
        (nitpick-test--on-line text 3
          (should (equal (nitpick--visit-line-side) '(parent . 1))))
        (nitpick-test--on-line text 7
          (should (equal (nitpick--visit-line-side) '(parent . 2))))
        (nitpick-test--on-line text 9
          (should (eq (nitpick--visit-line-side) 'both)))))))

(ert-deftest nitpick-test-visit-line-side-of-a-merges-removed-line ()
  "A `-' is the other shape: that parent has the line and the result does not."
  (let ((hunk (nitpick-test--hunk :combined t
                                  :from-range '((1 2) (1 2))
                                  :to-range '(1 2)
                                  :content 1)))
    (nitpick-test--with-stubs
        ((nitpick--oref (nitpick-test--oref-stub))
         (magit-diff--hunk-section (lambda () hunk)))
      (nitpick-test--on-line " -only theirs had it\n" 1
        (should (equal (nitpick--visit-line-side) '(parent . 2)))))))

(ert-deftest nitpick-test-visit-complement-is-the-other-side ()
  "What the modifier means, for every side a line can be on."
  (should (eq (nitpick--visit-complement 'old) 'new))
  (should (eq (nitpick--visit-complement 'new) 'old))
  (should (eq (nitpick--visit-complement 'both) 'old))
  ;; The conflicted file is where all of the parents are visible at once.
  (should (eq (nitpick--visit-complement '(parent . 2)) 'new)))

;;;; Visiting: which version that side names

(defmacro nitpick-test--with-sides (old new &rest body)
  "Run BODY with `magit-diff-visit--sides' answering OLD and NEW."
  (declare (indent 2))
  `(nitpick-test--with-stubs
       ((magit-diff-visit--sides (lambda () (list ,old ,new))))
     ,@body))

(ert-deftest nitpick-test-visit-target-takes-the-side-magit-names ()
  (nitpick-test--with-stubs
      ((magit-diff--hunk-section (lambda () nil)))
    (nitpick-test--with-sides '("abc123" "old.el") '("{worktree}" "new.el")
      (should (equal (nitpick--visit-target 'old) '("abc123" "old.el")))
      (should (equal (nitpick--visit-target 'new) '("{worktree}" "new.el")))
      (should (equal (nitpick--visit-target 'both) '("{worktree}" "new.el"))))))

(ert-deftest nitpick-test-visit-target-of-a-conflicts-parent-is-its-stage ()
  "Ours and theirs are stages 2 and 3 of the index.
Read by `nitpick--visit-stage-noselect', not `magit-find-file-noselect',
which answers a stage with an empty buffer."
  (let ((hunk (nitpick-test--conflict-hunk)))
    (nitpick-test--with-stubs
        ((nitpick--oref (nitpick-test--oref-stub))
         (magit-diff--hunk-section (lambda () hunk))
         (magit--file-index-stages
          (lambda (_) '(("100644" "baseoid" "1\tf.txt")
                        ("100644" "oursoid" "2\tf.txt")
                        ("100644" "theirsoid" "3\tf.txt")))))
      (nitpick-test--with-sides '("{worktree}" "f.txt") '("{worktree}" "f.txt")
        (should (equal (nitpick--visit-target '(parent . 1)) '(":2" "f.txt")))
        (should (equal (nitpick--visit-target '(parent . 2)) '(":3" "f.txt")))
        ;; The base has no column of its own, but it is stage 1.
        (should (equal (nitpick--visit-target 'old) '(":1" "f.txt")))))))

(ert-deftest nitpick-test-visit-target-of-a-merge-commits-parent ()
  "No index to read, so the parents are named off the commit itself."
  (let ((hunk (nitpick-test--conflict-hunk)))
    (nitpick-test--with-stubs
        ((nitpick--oref (nitpick-test--oref-stub))
         (magit-diff--hunk-section (lambda () hunk))
         (magit--file-index-stages (lambda (_) nil))
         (magit-git-string (lambda (&rest args)
                             (and (equal (car args) "merge-base") "base99"))))
      (let ((magit-buffer-revision "merge7"))
        (nitpick-test--with-sides '("{worktree}" "a.el") '("{worktree}" "a.el")
          (should (equal (nitpick--visit-target '(parent . 2))
                         '("merge7^2" "a.el")))
          (should (equal (nitpick--visit-target 'old) '("base99" "a.el"))))))))

(ert-deftest nitpick-test-visit-exists-p-asks-the-right-thing-per-rev ()
  (nitpick-test--with-stubs
      ((magit-toplevel (lambda (&rest _) "/tmp/wt/"))
       (magit-rev-verify (lambda (rev) (equal rev "abc123:a.el")))
       (magit--file-index-stages (lambda (_) '(("1"))))
       (file-exists-p (lambda (f) (equal f "/tmp/wt/live.el"))))
    (should (nitpick--visit-exists-p "{worktree}" "live.el"))
    (should-not (nitpick--visit-exists-p "{worktree}" "gone.el"))
    (should (nitpick--visit-exists-p "abc123" "a.el"))
    (should-not (nitpick--visit-exists-p "abc123" "added.el"))
    (should (nitpick--visit-exists-p "{index}" "a.el"))
    (should-not (nitpick--visit-exists-p nil "a.el"))))

(ert-deftest nitpick-test-visit-stage-is-read-into-its-own-buffer ()
  "magit answers a stage with an empty buffer, so the contents are read here."
  (let ((buffer nil))
    (unwind-protect
        (nitpick-test--with-stubs
            ((magit-toplevel (lambda (&rest _) "/tmp/wt/"))
             (magit-git-insert (lambda (&rest args)
                                 (should (equal args '("cat-file" "-p" ":2:f.txt")))
                                 (insert "ours\n"))))
          (setq buffer (nitpick--visit-stage-noselect 2 "f.txt"))
          (with-current-buffer buffer
            (should (equal (buffer-string) "ours\n"))
            (should buffer-read-only)
            ;; Not visiting the worktree file: saving this must not be possible.
            (should-not buffer-file-name)
            (should (equal (buffer-name) "f.txt.~:2~"))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest nitpick-test-visit-stage-spec-is-recognised ()
  (should (= (nitpick--visit-stage ":2") 2))
  (should-not (nitpick--visit-stage "abc123"))
  (should-not (nitpick--visit-stage "{worktree}"))
  (should-not (nitpick--visit-stage nil)))

(ert-deftest nitpick-test-visit-exists-p-of-a-stage-asks-the-index ()
  (nitpick-test--with-stubs
      ((magit--file-index-stages
        (lambda (_) '(("100644" "oid1" "1\tf.txt") ("100644" "oid2" "2\tf.txt")))))
    (should (nitpick--visit-exists-p ":1" "f.txt"))
    (should (nitpick--visit-exists-p ":2" "f.txt"))
    ;; A conflict where our side deleted the file has no stage 3.
    (should-not (nitpick--visit-exists-p ":3" "f.txt"))))

;;;; Visiting: which line

(ert-deftest nitpick-test-visit-line-asks-magit-for-the-sides-own-count ()
  "Both plain sides are counted for any line, which is what closes the gap."
  (let ((hunk (nitpick-test--hunk :combined nil))
        (asked nil))
    (nitpick-test--with-stubs
        ((nitpick--oref (nitpick-test--oref-stub))
         (magit-diff--hunk-section (lambda () hunk))
         (magit-diff-hunk-line (lambda (_section goto-from)
                                 (setq asked goto-from)
                                 (if goto-from 11 22))))
      (should (= (nitpick--visit-line 'old) 11))
      (should asked)
      (should (= (nitpick--visit-line 'new) 22))
      (should-not asked)
      (should (= (nitpick--visit-line 'both) 22)))))

(ert-deftest nitpick-test-visit-line-counts-a-combined-parents-own-column ()
  "Each side is counted in its own numbering: the parents by their column,
the result by every line no parent is missing."
  (let ((hunk (nitpick-test--conflict-hunk)))
    (nitpick-test--with-stubs
        ((nitpick--oref (nitpick-test--oref-stub))
         (magit-diff--hunk-section (lambda () hunk)))
      (let ((text nitpick-test--conflict-body))
        ;; Ours is top/OURS/bottom.
        (nitpick-test--on-line text 1
          (should (= (nitpick--visit-line '(parent . 1)) 1)))
        (nitpick-test--on-line text 3
          (should (= (nitpick--visit-line '(parent . 1)) 2)))
        (nitpick-test--on-line text 9
          (should (= (nitpick--visit-line '(parent . 1)) 3)))
        ;; Theirs is top/THEIRS/bottom.
        (nitpick-test--on-line text 7
          (should (= (nitpick--visit-line '(parent . 2)) 2)))
        ;; The conflicted file itself holds all nine lines.
        (nitpick-test--on-line text 3
          (should (= (nitpick--visit-line 'new) 3)))
        (nitpick-test--on-line text 7
          (should (= (nitpick--visit-line 'new) 7)))))))

(ert-deftest nitpick-test-visit-line-of-a-conflicts-base-is-nothing ()
  "A combined diff draws no base column, so there is no line to map to."
  (let ((hunk (nitpick-test--conflict-hunk)))
    (nitpick-test--with-stubs
        ((nitpick--oref (nitpick-test--oref-stub))
         (magit-diff--hunk-section (lambda () hunk)))
      (should-not (nitpick--visit-line 'old)))))

(ert-deftest nitpick-test-visit-line-outside-a-hunk-is-nothing ()
  (nitpick-test--with-stubs
      ((magit-diff--hunk-section (lambda () nil)))
    (should-not (nitpick--visit-line 'new))))

;;;; Visiting: the missing side opens the one that exists

(defmacro nitpick-test--visiting (&rest body)
  "Run BODY with the machinery a visit needs stubbed out, recording the opens.
`nitpick-test--opened' collects every (REV FILE) that was visited."
  (declare (indent 0))
  `(let ((nitpick-test--opened nil)
         (nitpick-test--said nil))
     (nitpick-test--with-stubs
         ((magit-find-file-noselect
           (lambda (rev file &rest _)
             (push (list rev file) nitpick-test--opened)
             (get-buffer-create " *nitpick-test-visited*")))
          (magit-diff-visit-file--setup (lambda (&rest _) nil))
          (pop-to-buffer-same-window (lambda (buffer &rest _) buffer))
          (message (lambda (fmt &rest args)
                     (setq nitpick-test--said (apply #'format fmt args))))
          (magit-diff--hunk-section (lambda () nil))
          (magit-toplevel (lambda (&rest _) "/tmp/wt/")))
       ,@body)))

(defvar nitpick-test--opened nil)
(defvar nitpick-test--said nil)

(ert-deftest nitpick-test-visit-opens-the-side-that-was-asked-for ()
  (nitpick-test--visiting
    (nitpick-test--with-stubs
        ((derived-mode-p (lambda (&rest modes) (memq 'magit-diff-mode modes)))
         (nitpick--visit-exists-p (lambda (&rest _) t)))
      (nitpick-test--with-sides '("abc123" "a.el") '("{worktree}" "a.el")
        (nitpick--visit-side 'old)
        (should (equal (car nitpick-test--opened) '("abc123" "a.el")))
        (nitpick--visit-side 'new)
        (should (equal (car nitpick-test--opened) '("{worktree}" "a.el")))
        (should-not nitpick-test--said)))))

(ert-deftest nitpick-test-visit-of-an-added-file-falls-back-to-the-worktree ()
  "Nothing in the base to open, so the key opens what there is, and says so."
  (nitpick-test--visiting
    (nitpick-test--with-stubs
        ((derived-mode-p (lambda (&rest modes) (memq 'magit-diff-mode modes)))
         (nitpick--visit-exists-p
          (lambda (rev &rest _) (equal rev "{worktree}"))))
      (nitpick-test--with-sides '("abc123" "new.el") '("{worktree}" "new.el")
        (nitpick--visit-side 'old)
        (should (equal (car nitpick-test--opened) '("{worktree}" "new.el")))
        (should (string-match-p "not in the base" nitpick-test--said))))))

(ert-deftest nitpick-test-visit-of-a-deleted-file-falls-back-to-the-base ()
  (nitpick-test--visiting
    (nitpick-test--with-stubs
        ((derived-mode-p (lambda (&rest modes) (memq 'magit-diff-mode modes)))
          (nitpick--visit-exists-p
           (lambda (rev &rest _) (not (equal rev "{worktree}")))))
      (nitpick-test--with-sides '("abc123" "gone.el") '("{worktree}" "gone.el")
        (nitpick--visit-side 'new)
        (should (equal (car nitpick-test--opened) '("abc123" "gone.el")))
        (should (string-match-p "not in the worktree" nitpick-test--said))))))

(ert-deftest nitpick-test-visit-refuses-when-neither-side-has-a-version ()
  (nitpick-test--visiting
    (nitpick-test--with-stubs
        ((derived-mode-p (lambda (&rest modes) (memq 'magit-diff-mode modes)))
         (nitpick--visit-exists-p (lambda (&rest _) nil)))
      (nitpick-test--with-sides '("abc123" "a.el") '("{worktree}" "a.el")
        (should-error (nitpick--visit-side 'new) :type 'user-error)
        (should-not nitpick-test--opened)))))

(ert-deftest nitpick-test-visit-refuses-outside-a-diff ()
  (nitpick-test--with-stubs
      ((derived-mode-p (lambda (&rest _) nil)))
    (should-error (nitpick--visit-side 'new) :type 'user-error)))

;;;; Visiting: the two commands

(ert-deftest nitpick-test-visit-follows-the-line-and-its-other-follows-back ()
  "The keystroke names the side; the line only says which one that is."
  (let ((visited nil))
    (nitpick-test--with-stubs
        ((nitpick--visit-line-side (lambda () 'old))
         (nitpick--visit-side (lambda (side &rest _) (setq visited side))))
      (nitpick-visit)
      (should (eq visited 'old))
      (nitpick-visit-other)
      (should (eq visited 'new)))))

(ert-deftest nitpick-test-visit-commands-take-a-prefix-to-the-picker ()
  (let ((picked 0))
    (nitpick-test--with-stubs
        ((nitpick-visit-pick (lambda () (setq picked (1+ picked))))
         (nitpick--visit-side (lambda (&rest _) (error "should have picked"))))
      (nitpick-visit t)
      (nitpick-visit-other t)
      (should (= picked 2)))))

(ert-deftest nitpick-test-visit-candidates-list-only-what-exists ()
  "The picker offers versions, not names of versions that are not there."
  (let ((hunk (nitpick-test--conflict-hunk)))
    (nitpick-test--with-stubs
        ((nitpick--oref (nitpick-test--oref-stub))
         (magit-diff--hunk-section (lambda () hunk))
         (magit--file-index-stages
          (lambda (_) '(("100644" "baseoid" "1\tf.txt")
                        ("100644" "oursoid" "2\tf.txt")
                        ("100644" "theirsoid" "3\tf.txt"))))
         (nitpick--visit-exists-p (lambda (rev _file)
                                    (not (equal rev ":3")))))
      (nitpick-test--with-sides '("{worktree}" "a.el") '("{worktree}" "a.el")
        (let ((labels (mapcar #'car (nitpick--visit-candidates))))
          (should (member "worktree" labels))
          (should (member "base" labels))
          (should (member "parent 1 (ours)" labels))
          ;; stage 3 is missing, so theirs is not offered
          (should-not (member "parent 2 (theirs)" labels)))))))

(ert-deftest nitpick-test-visit-pick-opens-what-was-named ()
  (let ((visited nil))
    (nitpick-test--with-stubs
        ((nitpick--visit-candidates (lambda () '(("worktree" . new)
                                                 ("base" . old))))
         (completing-read (lambda (&rest _) "base"))
         (nitpick--visit-side (lambda (side &rest _) (setq visited side))))
      (nitpick-visit-pick)
      (should (eq visited 'old)))))

;;;; The pane's own half of the rule

(ert-deftest nitpick-test-tree-node-side-is-the-one-the-file-is-in ()
  (should (eq (nitpick-tree--node-side '(:file "a.el" :status "M")) 'new))
  (should (eq (nitpick-tree--node-side '(:file "new.el" :status "A")) 'new))
  (should (eq (nitpick-tree--node-side '(:file "u.el" :status "?")) 'new))
  ;; A deleted file is in the base and nowhere else.
  (should (eq (nitpick-tree--node-side '(:file "gone.el" :status "D")) 'old)))

(ert-deftest nitpick-test-tree-node-target-names-the-side ()
  (with-temp-buffer
    (setq-local nitpick-tree--revision "origin/master")
    (should (equal (nitpick-tree--node-target '(:file "a.el") 'new)
                   '("{worktree}" "a.el")))
    (should (equal (nitpick-tree--node-target '(:file "a.el") 'old)
                   '("origin/master" "a.el")))
    ;; A rename is asked for by the name the side itself used.
    (should (equal (nitpick-tree--node-target
                    '(:file "new.el" :from "old.el") 'old)
                   '("origin/master" "old.el")))))

(ert-deftest nitpick-test-tree-node-line-is-read-off-the-diff ()
  "The pane already holds the diff, so opening the base runs no second one -
and it asks the same mapper the diff keys use, from the file's heading."
  (nitpick-test--with-windows (diff)
    (let ((nitpick-tree--diff-buffer diff)
          (asked nil)
          (where nil))
      (with-current-buffer diff (insert "diff\n"))
      (nitpick-test--with-stubs
          ((nitpick--oref (nitpick-test--oref-stub))
           (nitpick-tree--file-sections
            (lambda (&rest _)
              (list (nitpick-test--section 'file "a.el" 1))))
           (nitpick--visit-line (lambda (side)
                                  (setq asked side
                                        where (current-buffer))
                                  7)))
        (with-temp-buffer
          (setq-local nitpick-tree--root "/tmp/wt")
          (should (= (nitpick-tree--node-line '(:file "a.el") 'old) 7))
          (should (eq asked 'old))
          (should (eq where diff))
          ;; And the new side when that is the one being opened.
          (should (= (nitpick-tree--node-line '(:file "a.el") 'new) 7))
          (should (eq asked 'new)))))))

(ert-deftest nitpick-test-tree-visit-reads-the-line-from-the-pane ()
  "The revision, the root and the diff are pane locals, so the line has to be
worked out before another buffer is switched to - which is where it lands."
  (nitpick-test--with-windows (pane file)
    (let ((asked-in nil))
      (set-window-buffer (selected-window) pane)
      (with-current-buffer file (insert "one\ntwo\nthree\nfour\n"))
      (with-current-buffer pane
        (setq-local nitpick-tree--root "/tmp/wt"
                    nitpick-tree--revision "master")
        (nitpick-test--with-stubs
            ((nitpick-tree--node-line (lambda (&rest _)
                                        (setq asked-in (current-buffer))
                                        3))
             (nitpick--visit-exists-p (lambda (&rest _) t))
             (nitpick--base-revision (lambda (rev) rev))
             (magit-find-file-noselect (lambda (&rest _) file)))
          (nitpick-tree--visit-node '(:file "a.el" :status "D") 'old)
          (should (eq asked-in pane))
          (with-current-buffer file
            (should (= (line-number-at-pos) 3))))))))

(ert-deftest nitpick-test-tree-visit-opens-the-nodes-own-side ()
  (let ((visited nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--node-at-point (lambda () '(:file "a.el" :status "M")))
         (nitpick-tree--visit-node (lambda (_node side) (setq visited side))))
      (nitpick-tree-visit)
      (should (eq visited 'new))
      (nitpick-tree-visit-other)
      (should (eq visited 'old)))))

(ert-deftest nitpick-test-tree-visit-of-a-deleted-node-opens-the-base ()
  (let ((visited nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--node-at-point (lambda () '(:file "gone.el" :status "D")))
         (nitpick-tree--visit-node (lambda (_node side) (setq visited side))))
      (nitpick-tree-visit)
      (should (eq visited 'old))
      (nitpick-tree-visit-other)
      (should (eq visited 'new)))))

(ert-deftest nitpick-test-tree-visit-still-folds-a-directory ()
  "A directory has no version to open, so the key keeps its treemacs meaning."
  (let ((folded nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--node-at-point (lambda () '(:dir t :name "src")))
         (treemacs-node-at-point (lambda () (point)))
         (treemacs-expand-extension-node (lambda (&rest _) (setq folded 'open)))
         (nitpick-tree--visit-node (lambda (&rest _) (error "nothing to open"))))
      (with-temp-buffer
        (insert "src")
        (nitpick-tree-visit)
        (should (eq folded 'open))))))

(ert-deftest nitpick-test-tree-visit-other-ignores-a-directory ()
  (nitpick-test--with-stubs
      ((nitpick-tree--node-at-point (lambda () '(:dir t :name "src")))
       (nitpick-tree--visit-node (lambda (&rest _) (error "nothing to open"))))
    (should-not (nitpick-tree-visit-other))))

(ert-deftest nitpick-test-tree-pane-binds-the-two-visit-keys ()
  (should (eq (lookup-key nitpick-tree-mode-map "o") #'nitpick-tree-visit))
  (should (eq (lookup-key nitpick-tree-mode-map "O")
              #'nitpick-tree-visit-other)))

(ert-deftest nitpick-test-tree-untracked-preview-opens-the-file-either-way ()
  "git holds no other version of it, so both keys can only mean the file."
  (should (eq (lookup-key nitpick-tree-untracked-mode-map (kbd "RET"))
              #'nitpick-tree-untracked-visit))
  (should (eq (lookup-key nitpick-tree-untracked-mode-map (kbd "S-<return>"))
              #'nitpick-tree-untracked-visit))
  (unwind-protect
      (let ((opened nil))
        (nitpick-test--with-stubs
            ((nitpick-tree--git-output (lambda (&rest _) "+added\n"))
             (find-file-noselect (lambda (f &rest _)
                                   (setq opened f)
                                   (current-buffer)))
             (pop-to-buffer-same-window (lambda (buffer &rest _) buffer)))
          (with-current-buffer (nitpick-tree--untracked-diff "new.el" "/tmp/wt")
            (nitpick-tree-untracked-visit)
            (should (equal opened "/tmp/wt/new.el")))))
    (let ((buffer (get-buffer nitpick-tree-untracked-buffer-name)))
      (when buffer (kill-buffer buffer)))))

;;;; Reading the diff out of a patch

(defun nitpick-test--washed (value &rest props)
  "Return a stand-in for a washed file section holding VALUE and PROPS.
The slots `nitpick-tree--diff-changes' reads, which are not the ones the
sections built by `nitpick-test--section' carry."
  (append (list :type 'file :value value) props))

(defmacro nitpick-test--with-sections (sections &rest body)
  "Run BODY with SECTIONS standing in for the washed diff's file sections."
  (declare (indent 1))
  `(nitpick-test--with-stubs
       ((nitpick--oref (nitpick-test--oref-stub))
        (nitpick-tree--file-sections (lambda (_buffer) ,sections)))
     ,@body))

(ert-deftest nitpick-test-patch-status-reads-the-header ()
  "`new file' and `deleted file' are what the header says instead of a letter."
  (should (equal (nitpick-tree--patch-status "diff --git a a\nnew file mode 100644\n" nil)
                 "A"))
  (should (equal (nitpick-tree--patch-status
                  "diff --git a a\ndeleted file mode 100644\n" nil)
                 "D")))

(ert-deftest nitpick-test-patch-status-of-a-rename-is-its-source ()
  "magit keeps the old name in the section rather than in the header."
  (should (equal (nitpick-tree--patch-status "diff --git old new\n" "old.el") "R")))

(ert-deftest nitpick-test-patch-status-of-everything-else-is-modified ()
  "Which is what git's own `--name-status' answers for a mode change too."
  (should (equal (nitpick-tree--patch-status "diff --git a a\nindex 1..2\n" nil) "M")))

(ert-deftest nitpick-test-patch-counts-the-changed-lines ()
  "The `+' and `-' lines of the section, and nothing else in it."
  (with-temp-buffer
    (insert "modified   a.el\n"
            "@@ -1,3 +1,4 @@\n"
            " context\n"
            "-gone\n"
            "+new\n"
            "+more\n")
    (should (equal (nitpick-tree--count-changed (point-min) (point-max))
                   '(2 . 1)))))

(ert-deftest nitpick-test-patch-counts-nothing-in-an-empty-range ()
  "A binary file has no hunks at all."
  (with-temp-buffer
    (insert "modified   logo.png\n")
    (should (equal (nitpick-tree--count-changed (point-min) (point-max))
                   '(0 . 0)))))

(ert-deftest nitpick-test-patch-changes-read-the-diff-back ()
  "The pane's file list, taken out of the sections rather than out of git."
  (with-temp-buffer
    (insert "modified   a.el\n@@ -1 +1 @@\n-old\n+new\n")
    (nitpick-test--with-sections
        (list (nitpick-test--washed
               "a.el" :source nil :binary nil :header "diff --git a.el a.el\n"
               :start (point-min) :end (point-max)))
      (should (equal (nitpick-tree--diff-changes (current-buffer))
                     '((:file "a.el" :status "M" :from nil
                        :added 1 :deleted 1 :binary nil)))))))

(ert-deftest nitpick-test-patch-changes-keep-a-renames-source ()
  "The pane lists the new name and says where it came from."
  (with-temp-buffer
    (nitpick-test--with-sections
        (list (nitpick-test--washed
               "new.el" :source "old.el" :binary nil :header "diff --git x y\n"
               :start (point-min) :end (point-max)))
      (let ((change (car (nitpick-tree--diff-changes (current-buffer)))))
        (should (equal (plist-get change :status) "R"))
        (should (equal (plist-get change :from) "old.el"))))))

(ert-deftest nitpick-test-patch-changes-count-no-binary ()
  "Counted by neither side, the way git's own numstat leaves it."
  (with-temp-buffer
    (nitpick-test--with-sections
        (list (nitpick-test--washed
               "logo.png" :source nil :binary t :header "diff --git x x\n"
               :start (point-min) :end (point-max)))
      (let ((change (car (nitpick-tree--diff-changes (current-buffer)))))
        (should (plist-get change :binary))
        (should-not (plist-get change :added))
        (should-not (plist-get change :deleted))))))

(ert-deftest nitpick-test-patch-header-names-the-patch ()
  "And does not say `vs': what the forge diffed it against is not here."
  (let ((header (substring-no-properties
                 (nitpick-tree--header nil '(2 3 1) '(:label "o/r#7")))))
    (should (string-prefix-p " o/r#7" header))
    (should-not (string-match-p " vs " header))
    (should (string-match-p "2 files" header))))

(ert-deftest nitpick-test-patch-open-file-checks-out-first ()
  "A patch has no files: `o' is what asks for them."
  (let ((asked nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--check-out (lambda (node) (setq asked node)))
         (nitpick-tree--visit-node (lambda (&rest _) (error "Visited a patch"))))
      (let ((nitpick-tree--patch '(:label "o/r#7")))
        (nitpick-tree--open-file '(:file "a.el") 'new)
        (should (equal asked '(:file "a.el")))))))

(ert-deftest nitpick-test-patch-open-file-visits-a-checkout ()
  "With git as the source there is nothing to check out."
  (let ((visited nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--visit-node (lambda (node side) (setq visited (list node side)))))
      (let ((nitpick-tree--patch nil))
        (nitpick-tree--open-file '(:file "a.el") 'old)
        (should (equal visited '((:file "a.el") old)))))))

(ert-deftest nitpick-test-patch-visit-pick-checks-out-too ()
  "Both sides arrive with the checkout, so there is nothing to pick from."
  (let ((asked nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--node-at-point (lambda () '(:file "a.el")))
         (nitpick-tree--check-out (lambda (node) (setq asked node)))
         (completing-read (lambda (&rest _) (error "Asked which side"))))
      (let ((nitpick-tree--patch '(:label "o/r#7")))
        (nitpick-tree-visit-pick)
        (should (equal asked '(:file "a.el")))))))

(ert-deftest nitpick-test-range-target-names-both-revisions ()
  "Neither side is the worktree: the pane compares two revisions."
  (with-temp-buffer
    (setq-local nitpick-tree--patch '(:label "a..b" :sides ("rev-a" . "rev-b")))
    (should (equal (nitpick-tree--node-target '(:file "a.el") 'new)
                   '("rev-b" "a.el")))
    (should (equal (nitpick-tree--node-target '(:file "a.el") 'old)
                   '("rev-a" "a.el")))
    ;; A rename is still asked for by the name the side itself used.
    (should (equal (nitpick-tree--node-target
                    '(:file "new.el" :from "old.el") 'old)
                   '("rev-a" "old.el")))))

(ert-deftest nitpick-test-range-opens-blobs-rather-than-checking-out ()
  "git holds both sides already, so there is nothing to fetch."
  (let ((visited nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--visit-node (lambda (node side) (setq visited (list node side))))
         (nitpick-tree--check-out (lambda (&rest _) (error "Checked a range out"))))
      (let ((nitpick-tree--patch '(:label "a..b" :sides ("rev-a" . "rev-b"))))
        (nitpick-tree--open-file '(:file "a.el") 'new)
        (should (equal visited '((:file "a.el") new)))))))

(ert-deftest nitpick-test-range-visit-pick-offers-the-two-revisions ()
  "Not `worktree' and `base': the pane has neither."
  (let ((offered nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--node-at-point (lambda () '(:file "a.el")))
         (nitpick--visit-exists-p (lambda (&rest _) t))
         (nitpick-tree--visit-node #'ignore)
         (completing-read (lambda (_prompt candidates &rest _)
                            (setq offered (mapcar #'car candidates))
                            "rev-a")))
      (let ((nitpick-tree--patch '(:label "a..b" :sides ("rev-a" . "rev-b"))))
        (with-temp-buffer
          (setq-local nitpick-tree--root "/tmp/wt")
          (nitpick-tree-visit-pick)
          (should (equal offered '("rev-b" "rev-a"))))))))

(ert-deftest nitpick-test-range-source-carries-the-sides-and-the-diff ()
  "What the pane drives a range with: a label, the two sides, one diff."
  (let ((asked nil))
    (nitpick-test--with-stubs
        ((nitpick-tree--range-diff (lambda (root range)
                                     (setq asked (list root range))
                                     'buffer)))
      (let ((source (nitpick-tree--range-source
                     "/tmp/wt" "a...b" '("base" . "b"))))
        (should (equal (plist-get source :label) "a...b"))
        (should (equal (plist-get source :sides) '("base" . "b")))
        (should-not (plist-get source :check-out))
        (should (eq (funcall (plist-get source :diff)) 'buffer))
        (should (equal asked '("/tmp/wt" "a...b")))))))

(ert-deftest nitpick-test-range-command-opens-the-pane-on-a-range ()
  "A three-dot range keeps its own spelling; the sides are resolved once."
  (let ((opened nil))
    (nitpick-test--with-stubs
        ((magit-split-range (lambda (&rest _) '("merge-base" . "theirs")))
         (nitpick-tree (lambda (root revision &optional patch)
                         (setq opened (list root revision patch)))))
      (nitpick-tree-range "/tmp/wt" "ours...theirs")
      (should (equal (nth 0 opened) "/tmp/wt"))
      (should-not (nth 1 opened))
      (should (equal (plist-get (nth 2 opened) :label) "ours...theirs"))
      (should (equal (plist-get (nth 2 opened) :sides)
                     '("merge-base" . "theirs"))))))

(ert-deftest nitpick-test-range-command-of-a-bare-revision-is-the-review ()
  "One revision means the worktree is the other side after all."
  (let ((opened nil))
    (nitpick-test--with-stubs
        ((magit-split-range (lambda (&rest _) nil))
         (nitpick-tree (lambda (root revision &optional patch)
                         (setq opened (list root revision patch)))))
      (nitpick-tree-range "/tmp/wt" "origin/master")
      (should (equal opened '("/tmp/wt" "origin/master" nil))))))

(ert-deftest nitpick-test-patch-check-out-runs-what-the-patch-carries ()
  "The patch owns how it is materialised; the pane only asks."
  (let ((callback nil))
    (let ((nitpick-tree--patch
           (list :check-out (lambda (file cb)
                              (should (equal file "dir/a.el"))
                              (setq callback cb)))))
      (nitpick-tree--check-out '(:file "dir/a.el"))
      (should (functionp callback))
      (nitpick-test--with-stubs
          ((nitpick-tree--adopt (lambda (root file) (list root file))))
        (should (equal (funcall callback "/tmp/wt") '("/tmp/wt" "dir/a.el")))))))

(ert-deftest nitpick-test-patch-check-out-needs-a-file ()
  "A directory, or the space between nodes, is not something to check out for."
  (let ((nitpick-tree--patch (list :check-out (lambda (&rest _) nil))))
    (should-error (nitpick-tree--check-out nil) :type 'user-error)))

(ert-deftest nitpick-test-patch-goto-file-finds-the-pane-line ()
  "The pane is drawn expanded, so the line for a file is there to be found."
  (nitpick-test--with-stubs
      ((treemacs-node-at-point (lambda () (point))))
    (with-temp-buffer
      (insert (propertize "a.el\n" :nitpick-node '(:file "a.el")))
      (insert (propertize "b.el\n" :nitpick-node '(:file "dir/b.el")))
      (should (nitpick-tree--goto-file "dir/b.el"))
      (should (equal (line-number-at-pos) 2))
      (should-not (nitpick-tree--goto-file "nowhere.el")))))

(ert-deftest nitpick-test-tree-goto-node-skips-the-line-above-the-first ()
  "treemacs owns the top line, and the diff cannot follow a point with no node."
  (nitpick-test--with-stubs
      ((treemacs-node-at-point (lambda () (point))))
    (with-temp-buffer
      (insert "\n" (propertize "a.el\n" :nitpick-node '(:file "a.el")))
      (goto-char (point-min))
      (nitpick-tree--goto-node)
      (should (equal (line-number-at-pos) 2)))))

(ert-deftest nitpick-test-tree-goto-node-stays-where-a-node-is ()
  "A refresh puts the point back on the line being read; it must stay there."
  (nitpick-test--with-stubs
      ((treemacs-node-at-point (lambda () (point))))
    (with-temp-buffer
      (insert (propertize "a.el\n" :nitpick-node '(:file "a.el"))
              (propertize "b.el\n" :nitpick-node '(:file "b.el")))
      (goto-char (point-min))
      (forward-line 1)
      (nitpick-tree--goto-node)
      (should (equal (line-number-at-pos) 2)))))

(ert-deftest nitpick-test-patch-adopt-re-reads-from-git ()
  "The worktree is a checkout like any other, so the pane it gets is git's."
  (let ((opened nil)
        (visited nil))
    (nitpick-test--with-stubs
        ((nitpick-diff-hl--suggested-base (lambda (_root) "origin/master"))
         (nitpick-tree--open (lambda (&rest args) (setq opened args)))
         (nitpick-tree--goto-file (lambda (_file) t))
         (nitpick-tree-visit (lambda (&rest _) (setq visited t))))
      (let ((pane (get-buffer-create nitpick-tree-buffer-name))
            (nitpick-tree--diff-buffer (current-buffer)))
        (unwind-protect
            (progn
              (nitpick-tree--adopt "/tmp/wt" "a.el")
              (should (equal opened '("/tmp/wt" "origin/master")))
              (should visited)
              ;; The patch's diff is not the checkout's: the next reveal
              ;; reads one.
              (should-not nitpick-tree--diff-buffer))
          (kill-buffer pane))))))

;;;; Naming a pull request

(ert-deftest nitpick-test-pr-parses-a-github-url ()
  "Handed to both tools as it stands: it names its own repository."
  (nitpick-test--with-stubs ((magit-toplevel (lambda (&rest _) "/tmp/wt/")))
    (let ((pr (nitpick-pr--parse "https://github.com/o/r/pull/42")))
      (should (equal (plist-get pr :label) "o/r#42"))
      (should (equal (plist-get pr :args) '("https://github.com/o/r/pull/42")))
      (should (equal (plist-get pr :ref) "https://github.com/o/r/pull/42")))))

(ert-deftest nitpick-test-pr-parses-a-forgejo-url ()
  "Forgejo, Gitea and Codeberg spell the path `pulls'."
  (nitpick-test--with-stubs ((magit-toplevel (lambda (&rest _) "/tmp/wt/")))
    (should (equal (plist-get (nitpick-pr--parse "https://codeberg.org/o/r/pulls/7")
                              :label)
                   "o/r#7"))))

(ert-deftest nitpick-test-pr-parses-the-gh-dash-spelling ()
  "owner/repo#number, which is what the review keys are given."
  (nitpick-test--with-stubs ((magit-toplevel (lambda (&rest _) "/tmp/wt/")))
    (let ((pr (nitpick-pr--parse "dlvhdr/gh-dash#447")))
      (should (equal (plist-get pr :args) '("--repo" "dlvhdr/gh-dash" "447")))
      (should (equal (plist-get pr :ref)
                     "https://github.com/dlvhdr/gh-dash/pull/447")))))

(ert-deftest nitpick-test-pr-parses-a-bare-number-against-the-repo-at-hand ()
  "The only spelling that needs one, so it is the only one that asks."
  (nitpick-test--with-stubs
      ((magit-toplevel (lambda (&rest _) "/tmp/wt/")))
    (let ((pr (nitpick-pr--parse "#42")))
      (should (equal (plist-get pr :label) "#42"))
      (should (equal (plist-get pr :args) '("42")))
      (should (equal (plist-get pr :ref) "42"))
      (should (equal (plist-get pr :dir) "/tmp/wt/")))))

(ert-deftest nitpick-test-pr-bare-number-needs-a-repository ()
  "Nothing resolves `#42' on its own."
  (nitpick-test--with-stubs
      ((magit-toplevel (lambda (&rest _) nil)))
    (should-error (nitpick-pr--parse "42") :type 'user-error)))

(ert-deftest nitpick-test-pr-refuses-what-is-not-a-pull-request ()
  "A branch name is not one, and must not be read as a number either."
  (should-error (nitpick-pr--parse "origin/master") :type 'user-error))

(ert-deftest nitpick-test-pr-patch-file-is-named-after-the-label ()
  "One file per pull request, and nothing in the name that needs quoting."
  (let ((nitpick-pr-directory "/tmp/nitpick-test"))
    (should (equal (file-name-nondirectory
                    (nitpick-pr--patch-file '(:label "o/r#42")))
                   "o-r-42.diff"))))

;;;; The patch as magit's own sections

(defun nitpick-test--stripped (patch)
  "Return PATCH with the a/ and b/ prefixes taken out of its headers."
  (with-temp-buffer
    (insert patch)
    (nitpick-pr--strip-prefixes)
    (buffer-string)))

(ert-deftest nitpick-test-pr-strips-the-path-prefixes ()
  "magit's washer reads what `--no-prefix' writes; a forge serves prefixes."
  (should (equal (nitpick-test--stripped
                  "diff --git a/src/a.el b/src/a.el\nindex 1..2 100644\n--- a/src/a.el\n+++ b/src/a.el\n@@ -1 +1 @@\n-old\n+new\n")
                 "diff --git src/a.el src/a.el\nindex 1..2 100644\n--- src/a.el\n+++ src/a.el\n@@ -1 +1 @@\n-old\n+new\n")))

(ert-deftest nitpick-test-pr-strips-a-path-with-a-space-in-it ()
  "git quotes the unusual characters but not a space, so the names are equal."
  (should (equal (nitpick-test--stripped "diff --git a/with space.el b/with space.el\n")
                 "diff --git with space.el with space.el\n")))

(ert-deftest nitpick-test-pr-keeps-dev-null ()
  "The side an added or deleted file does not have is not a path."
  (should (equal (nitpick-test--stripped
                  "diff --git a/new.el b/new.el\nnew file mode 100644\n--- /dev/null\n+++ b/new.el\n")
                 "diff --git new.el new.el\nnew file mode 100644\n--- /dev/null\n+++ new.el\n")))

(ert-deftest nitpick-test-pr-keeps-both-names-of-a-rename ()
  "The two names differ, so only the ones git writes unprefixed stand."
  (should (equal (nitpick-test--stripped
                  "diff --git a/old.el b/new.el\nrename from old.el\nrename to new.el\n--- a/old.el\n+++ b/new.el\n")
                 "diff --git a/old.el b/new.el\nrename from old.el\nrename to new.el\n--- old.el\n+++ new.el\n")))

(ert-deftest nitpick-test-pr-strips-a-binary-header ()
  "A binary file has no `---' lines, so this header is the only name magit gets."
  (should (equal (nitpick-test--stripped
                  "diff --git a/logo.png b/logo.png\nindex 1..2 100644\nBinary files a/logo.png and b/logo.png differ\n")
                 "diff --git logo.png logo.png\nindex 1..2 100644\nBinary files logo.png and logo.png differ\n")))

(ert-deftest nitpick-test-pr-leaves-a-patch-of-a-patch-alone ()
  "Inside a hunk, a line that looks like a header is content."
  (let ((patch (concat "diff --git a/p.diff b/p.diff\n"
                       "--- a/p.diff\n"
                       "+++ b/p.diff\n"
                       "@@ -1,2 +1,2 @@\n"
                       "-diff --git a/x b/x\n"
                       "+--- a/y\n")))
    (should (equal (nitpick-test--stripped patch)
                   (concat "diff --git p.diff p.diff\n"
                           "--- p.diff\n"
                           "+++ p.diff\n"
                           "@@ -1,2 +1,2 @@\n"
                           "-diff --git a/x b/x\n"
                           "+--- a/y\n")))))

(ert-deftest nitpick-test-pr-patch-buffer-remaps-the-visit-keys ()
  "RET on a hunk is bound in magit's section maps, which outrank a mode map."
  (should (eq (lookup-key nitpick-pr-patch-mode-map [remap nitpick-visit])
              #'nitpick-pr-visit))
  (should (eq (lookup-key nitpick-pr-patch-mode-map [remap nitpick-visit-other])
              #'nitpick-pr-visit))
  (should (eq (lookup-key nitpick-pr-patch-mode-map [remap nitpick-comment])
              #'nitpick-pr-comment)))

;;;; Checking a pull request out

(defmacro nitpick-test--with-errors (text &rest body)
  "Run BODY with `buffer' bound to a stderr buffer holding TEXT."
  (declare (indent 1))
  `(let ((buffer (generate-new-buffer " *nitpick-test-errors*")))
     (unwind-protect
         (progn (with-current-buffer buffer (insert ,text)) ,@body)
       (kill-buffer buffer))))

(defun nitpick-test--job (&rest props)
  "Return a job plist with a live-looking process and PROPS."
  (append props (list :process 'live)))

(defmacro nitpick-test--with-jobs (jobs &rest body)
  "Run BODY with JOBS registered and every registered process alive."
  (declare (indent 1))
  `(nitpick-test--with-stubs
       ((process-live-p (lambda (process) (eq process 'live))))
     (let ((nitpick-pr--jobs ,jobs))
       ,@body)))

(ert-deftest nitpick-test-pr-reads-the-worktree-off-the-last-line ()
  "`git pr' prints the path last, and only on stdout."
  (nitpick-test--with-stubs
      ((file-directory-p (lambda (_path) t)))
    (should (equal (nitpick-pr--worktree "reusing session\n/tmp/wt/PROJ-1-feat\n")
                   "/tmp/wt/PROJ-1-feat"))))

(ert-deftest nitpick-test-pr-worktree-must-be-a-directory ()
  "Anything else printed is progress, not a path."
  (nitpick-test--with-stubs
      ((file-directory-p (lambda (_path) nil)))
    (should-not (nitpick-pr--worktree "git pr: reusing session\n"))))

(ert-deftest nitpick-test-pr-complaint-is-the-last-line ()
  "Progress comes first; the reason it stopped is what it said last."
  (nitpick-test--with-errors
      "git pr: fetching refs/pull/7/head\ngit pr: no clone of github.com/o/r\n"
    (should (equal (nitpick-pr--complaint buffer)
                   "git pr: no clone of github.com/o/r"))))

(ert-deftest nitpick-test-pr-complaint-of-an-empty-buffer-is-nothing ()
  "A failure that said nothing must not be reported as an empty line."
  (nitpick-test--with-errors ""
    (should-not (nitpick-pr--complaint buffer))))

(ert-deftest nitpick-test-pr-progress-ignores-what-is-not-progress ()
  "Before git starts counting there is nothing to report but our own line."
  (nitpick-test--with-errors "git pr: cloning git@github.com:o/r.git into /cache/o/r\n"
    (should-not (nitpick-pr--progress buffer))))

(ert-deftest nitpick-test-pr-progress-is-the-last-return-chunk ()
  "Git overwrites one line with `\\r', so the percent is not on a line of its own."
  (nitpick-test--with-errors
      "Cloning into bare repository\nReceiving objects:   1% (1/7540)\rReceiving objects:  43% (3243/7540)\r"
    (should (equal (nitpick-pr--progress buffer)
                   "Receiving objects:  43% (3243/7540)"))))

(ert-deftest nitpick-test-pr-cloned-p-reads-what-git-pr-said ()
  "Nothing is cloned when the repository was already there, and saying so would lie."
  (nitpick-test--with-errors "git pr: cloning github.com/o/r into /cache/o/r\n"
    (should (nitpick-pr--cloned-p buffer)))
  (nitpick-test--with-errors "git pr: reusing existing worktree at /wt/pr-7\n"
    (should-not (nitpick-pr--cloned-p buffer))))

(ert-deftest nitpick-test-pr-clone-flags-per-phase ()
  "A clone job stops at the clone; a checkout job may make one on the way."
  (should (equal (nitpick-pr--flags 'clone) '("--clone-only")))
  (let ((nitpick-pr-clone 'prefetch))
    (should (equal (nitpick-pr--flags 'checkout) '("--clone"))))
  (let ((nitpick-pr-clone 'on-demand))
    (should (equal (nitpick-pr--flags 'checkout) '("--clone"))))
  (let ((nitpick-pr-clone nil))
    (should-not (nitpick-pr--flags 'checkout))))

(ert-deftest nitpick-test-pr-clone-directory-reaches-the-process ()
  "And is absent when unset, so the default stays `git pr's to pick."
  (let ((nitpick-pr-clone-directory "/data/clones"))
    (should (member "GIT_PR_CLONE_ROOT=/data/clones" (nitpick-pr--environment))))
  (let ((nitpick-pr-clone-directory nil))
    (should-not (seq-find (lambda (entry)
                            (string-prefix-p "GIT_PR_CLONE_ROOT=" entry))
                          (nitpick-pr--environment)))))

(ert-deftest nitpick-test-pr-land-opens-what-the-checkout-made ()
  "Which is what the pane re-reads itself from."
  (let ((landed nil))
    (nitpick-test--with-stubs
        ((file-directory-p (lambda (_path) t)))
      (nitpick-test--with-jobs
          (list (cons "o/r#7"
                      (nitpick-test--job
                       :phase 'checkout :file "a.el"
                       :pending (lambda (root) (setq landed root)))))
        (nitpick-pr--land '(:label "o/r#7") 0 "/tmp/wt\n")
        (should (equal landed "/tmp/wt"))
        ;; And the job is forgotten, so the next `o' starts a new one.
        (should-not nitpick-pr--jobs)))))

(ert-deftest nitpick-test-pr-land-failure-opens-nothing-and-says-why ()
  "A fetch that failed must not send the pane at a worktree that is not there."
  (let ((landed nil))
    (nitpick-test--with-errors "fatal: could not read Username\n"
      (nitpick-test--with-jobs
          (list (cons "o/r#7"
                      (nitpick-test--job
                       :phase 'checkout :errors buffer
                       :pending (lambda (root) (setq landed root)))))
        (should (equal (nitpick-test--messaged
                        (lambda () (nitpick-pr--land '(:label "o/r#7") 1 "")))
                       "nitpick-pr: fatal: could not read Username"))
        (should-not landed)))))

(ert-deftest nitpick-test-pr-land-failure-without-a-reason-names-the-buffer ()
  "Nothing on stderr leaves the buffer as the only place left to look."
  (nitpick-test--with-errors ""
    (nitpick-test--with-jobs
        (list (cons "o/r#7" (nitpick-test--job :phase 'checkout :errors buffer)))
      (should (string-match-p "git pr failed for o/r#7"
                              (nitpick-test--messaged
                               (lambda ()
                                 (nitpick-pr--land '(:label "o/r#7") 1 ""))))))))

(ert-deftest nitpick-test-pr-land-of-a-clone-starts-what-waited-for-it ()
  "The visit that asked for the files carries on where it left off."
  (let ((started nil)
        (pending (lambda (_root) nil)))
    (nitpick-test--with-stubs
        ((nitpick-pr--start (lambda (_pr phase &optional file callback)
                              (setq started (list phase file callback)))))
      (nitpick-test--with-errors "git pr: cloning github.com/o/r into /cache/o/r\n"
        (nitpick-test--with-jobs
            (list (cons "o/r#7"
                        (nitpick-test--job :phase 'clone :errors buffer
                                           :file "a.el" :pending pending)))
          (nitpick-pr--land '(:label "o/r#7") 0 "/cache/o/r\n")
          (should (equal started (list 'checkout "a.el" pending))))))))

(ert-deftest nitpick-test-pr-land-of-a-prefetch-waits-for-nothing ()
  "A clone nobody asked to visit yet is the end of it."
  (let ((started nil))
    (nitpick-test--with-stubs
        ((nitpick-pr--start (lambda (&rest args) (setq started args))))
      (nitpick-test--with-errors "git pr: cloning github.com/o/r into /cache/o/r\n"
        (nitpick-test--with-jobs
            (list (cons "o/r#7" (nitpick-test--job :phase 'clone :errors buffer)))
          (nitpick-pr--land '(:label "o/r#7") 0 "/cache/o/r\n")
          (should-not started))))))

(ert-deftest nitpick-test-pr-check-out-joins-the-job-in-flight ()
  "Two `o's are one `git pr': the second waits on the clone the first started."
  (let ((started nil)
        (callback (lambda (_root) nil)))
    (nitpick-test--with-stubs
        ((nitpick-pr--start (lambda (&rest args) (setq started args))))
      (nitpick-test--with-errors "Receiving objects:  43% (3243/7540)\r"
        (let ((job (nitpick-test--job :phase 'clone :errors buffer)))
          (nitpick-test--with-jobs (list (cons "o/r#7" job))
            (should (string-match-p
                     "cloning o/r#7 - Receiving objects:  43% (3243/7540) - will open a\\.el"
                     (nitpick-test--messaged
                      (lambda ()
                        (nitpick-pr--check-out '(:label "o/r#7") "a.el" callback)))))
            (should-not started)
            (should (eq (plist-get job :pending) callback))
            (should (equal (plist-get job :file) "a.el"))))))))

(ert-deftest nitpick-test-pr-check-out-starts-one-when-nothing-runs ()
  "The ordinary case, and the only one under `nitpick-pr-clone' nil."
  (let ((started nil)
        (callback (lambda (_root) nil)))
    (nitpick-test--with-stubs
        ((nitpick-pr--start (lambda (_pr phase &optional file cb)
                              (setq started (list phase file cb)))))
      (nitpick-test--with-jobs nil
        (nitpick-pr--check-out '(:label "o/r#7") "a.el" callback)
        (should (equal started (list 'checkout "a.el" callback)))))))

(ert-deftest nitpick-test-pr-prefetch-only-when-asked ()
  "`prefetch' starts the clone as the pane opens; the other two do not."
  (let ((started nil))
    (nitpick-test--with-stubs
        ((nitpick-pr--start (lambda (_pr phase &rest _) (push phase started))))
      (nitpick-test--with-jobs nil
        (let ((nitpick-pr-clone 'prefetch))
          (nitpick-pr--prefetch '(:label "o/r#7")))
        (let ((nitpick-pr-clone 'on-demand))
          (nitpick-pr--prefetch '(:label "o/r#7")))
        (let ((nitpick-pr-clone nil))
          (nitpick-pr--prefetch '(:label "o/r#7")))
        (should (equal started '(clone)))))))

(ert-deftest nitpick-test-pr-prefetch-does-not-double-a-job ()
  "Reading the same pull request again joins what is already running."
  (let ((started nil)
        (nitpick-pr-clone 'prefetch))
    (nitpick-test--with-stubs
        ((nitpick-pr--start (lambda (&rest args) (setq started args))))
      (nitpick-test--with-jobs
          (list (cons "o/r#7" (nitpick-test--job :phase 'clone)))
        (nitpick-pr--prefetch '(:label "o/r#7"))
        (should-not started)))))

(ert-deftest nitpick-test-pr-prefetch-survives-a-missing-git-pr ()
  "A tool that is not installed must not stop a pull request from opening."
  (let ((nitpick-pr-clone 'prefetch))
    (nitpick-test--with-stubs
        ((nitpick-pr--git-pr (lambda () (user-error "`git pr' is not available"))))
      (nitpick-test--with-jobs nil
        (should (string-match-p "not prefetching o/r#7"
                                (nitpick-test--messaged
                                 (lambda ()
                                   (nitpick-pr--prefetch '(:label "o/r#7"))))))))))

(ert-deftest nitpick-test-pr-job-forgets-a-process-that-stopped ()
  "Otherwise a job that failed would swallow every `o' after it."
  (nitpick-test--with-stubs
      ((process-live-p (lambda (_process) nil)))
    (let ((nitpick-pr--jobs (list (cons "o/r#7" (list :process 'dead)))))
      (should-not (nitpick-pr--job "o/r#7"))
      (should-not nitpick-pr--jobs))))

(provide 'nitpick-test)
;;; nitpick-test.el ends here
