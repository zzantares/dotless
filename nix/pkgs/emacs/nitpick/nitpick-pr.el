;;; nitpick-pr.el --- Read a pull request before checking it out -*- lexical-binding: t; -*-

;; Author: dotless
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (magit "4.0"))
;; Keywords: vc, tools
;; URL: https://git.gutimore.net/gutimore/dotless

;;; Commentary:

;; `nitpick-pr' reads a pull request the way `gh pr diff | diffnav' does: name
;; it by URL, by owner/repo#number or by number, and the pane opens on the
;; patch the forge serves - no clone, no fetch, no worktree.  The diff beside
;; it is magit's own, washed out of the patch text rather than read from `git
;; diff', so the pane's keys all work on it.
;;
;; What a patch cannot give is the files: there is nothing for `o' to open and
;; nothing for `nitpick-comment' to anchor a thread on.  So the first of those
;; checks the pull request out - `git pr', which finds the clone, fetches
;; refs/pull/N/head and leaves it in a sibling worktree - and the pane is
;; re-read from git there, ending on the file that asked for it.  Reading a PR
;; costs one `gh' call; only a review that opens a file pays for a worktree.

;;; Code:

(require 'nitpick)
(require 'nitpick-tree)

(declare-function magit-diff-mode "magit-diff" ())
(declare-function magit-diff-wash-diffs "magit-diff" (args &optional limit))
(declare-function magit-file-at-point "magit-git" (&optional expand assert))
(declare-function magit-refresh-buffer "magit-mode" (&optional created &rest args))
(declare-function magit-set-header-line-format "magit-mode" (string))
(declare-function magit-toplevel "magit-git" (&optional directory))
(defvar magit-diff-mode-map)

;;;; Options

(defcustom nitpick-pr-git-pr-executable "git-pr"
  "The `git pr' front end that checks a pull request out.
From dotless' pr-tools, which nix pins to a store path: it finds the clone
the PR names, fetches refs/pull/N/head and leaves it in a sibling worktree."
  :type 'string
  :group 'nitpick)

(defcustom nitpick-pr-directory (expand-file-name "nitpick" temporary-file-directory)
  "Where the patches read from the forge are kept.
One file per pull request, overwritten by the next read of it."
  :type 'directory
  :group 'nitpick)

(defcustom nitpick-pr-clone 'prefetch
  "When to make the clone a pull request of an unknown repository needs.
`git pr\=' adds a worktree to a clone you have; it clones only when asked.

`prefetch\=' asks as the pane opens, so the clone is usually there by the time
a file is - that is the whole point of it being in the background.  Nothing is
cloned if the repository is already somewhere `git pr\=' looks, and asking
costs milliseconds when it is.

`on-demand\=' asks at the first `o\=' instead, and nil never does - which
leaves `o\=' failing on a repository you do not have, as it did before."
  :type '(choice (const :tag "As the pane opens" prefetch)
                 (const :tag "At the first visit" on-demand)
                 (const :tag "Never" nil))
  :group 'nitpick)

(defcustom nitpick-pr-clone-directory nil
  "Where a clone made for a review goes, or nil for `git pr\='s own default.
`<directory>/<owner>/<repo>\=', which is the layout `git pr\=' looks in, so a
repository is cloned once however the next review reaches it.  Its worktrees
land beside it, so point this at somewhere you keep work if you mean to
contribute to what you review.

Nil leaves the choice to `git pr\=', which keeps them in a cache directory
under $XDG_CACHE_HOME - disposable, and pruned by nothing but you."
  :type '(choice (const :tag "git pr\='s own cache directory" nil)
                 directory)
  :group 'nitpick)

;;;; Naming a pull request

(defconst nitpick-pr--url-re
  "\\`https?://[^/]+/\\([^/]+/[^/]+\\)/pulls?/\\([0-9]+\\)"
  "A pull request named by its own URL.
`/pull/' is GitHub's and `/pulls/' is Forgejo's and Gitea's.")

(defconst nitpick-pr--slug-re "\\`\\([^ /]+/[^ /#]+\\)#\\([0-9]+\\)\\'"
  "A pull request named as owner/repo#number, the way gh-dash spells it.")

(defconst nitpick-pr--number-re "\\`#?\\([0-9]+\\)\\'"
  "A pull request named by number alone - one of the repository at hand.")

(defun nitpick-pr--parse (spec)
  "Return a plist naming the pull request SPEC points at.
Keys: `:label' for the header line, `:args' for `gh', `:ref' for `git pr',
and `:dir', the directory both are run from.

A URL is handed to both tools as it stands, so the repository it names is the
one they answer for.  A bare number is a pull request of the repository the
point is in, which is the only spelling that needs one."
  (let ((spec (string-trim spec)))
    (cond
     ((string-match nitpick-pr--url-re spec)
      (list :label (format "%s#%s" (match-string 1 spec) (match-string 2 spec))
            :args (list spec)
            :ref spec
            :dir (nitpick-pr--dir)))
     ((string-match nitpick-pr--slug-re spec)
      (let ((repo (match-string 1 spec))
            (number (match-string 2 spec)))
        (list :label spec
              :args (list "--repo" repo number)
              ;; What `pr-diff' builds for the same spelling, so both review
              ;; keys check the same URL out.
              :ref (format "https://github.com/%s/pull/%s" repo number)
              :dir (nitpick-pr--dir))))
     ((string-match nitpick-pr--number-re spec)
      (let ((number (match-string 1 spec)))
        (list :label (concat "#" number)
              :args (list number)
              :ref number
              :dir (or (magit-toplevel)
                       (user-error "A bare number names a PR of the repository you are in")))))
     (t (user-error "Not a pull request: %s" spec)))))

(defun nitpick-pr--directory ()
  "Return `nitpick-pr-directory', made if it is not there yet."
  (let ((dir (file-name-as-directory nitpick-pr-directory)))
    (make-directory dir t)
    dir))

(defun nitpick-pr--dir ()
  "Return the directory `gh' and `git pr' are run from.
The repository at hand when there is one: `git pr' looks for the clone a URL
names there first, and a review is usually started from it."
  (or (magit-toplevel) (nitpick-pr--directory)))

(defun nitpick-pr--patch-file (pr)
  "Return the file PR's patch is kept in."
  (expand-file-name
   (format "%s.diff"
           (string-trim (replace-regexp-in-string "[^A-Za-z0-9]+" "-"
                                                  (plist-get pr :label))
                        "-" "-"))
   (nitpick-pr--directory)))

(defun nitpick-pr--read (pr)
  "Ask the forge for PR's diff, and return the file it was written to.
`gh pr diff', which serves the three-dot diff the forge's own \"Files
changed\" shows.  Overwritten on every read: the file is one request cached,
not a document."
  (let ((gh (nitpick--gh))
        (file (nitpick-pr--patch-file pr))
        (default-directory (plist-get pr :dir)))
    (with-temp-buffer
      ;; Stderr lands here too, so a failure can say why; `gh' keeps its
      ;; release notices for a terminal.
      (unless (= 0 (apply #'call-process gh nil t nil "pr" "diff"
                          (plist-get pr :args)))
        (error "gh pr diff failed for %s:\n%s"
               (plist-get pr :label) (string-trim (buffer-string))))
      (when (= (point-min) (point-max))
        (user-error "%s changes nothing" (plist-get pr :label)))
      (write-region (point-min) (point-max) file nil 'silent))
    file))

;;;; The patch as a magit diff buffer

(defvar-local nitpick-pr--pr nil
  "The pull request this buffer's patch came from.")

(defvar-local nitpick-pr--file nil
  "The patch file this buffer was washed from.")

(defun nitpick-pr--buffer-name (pr)
  "Return the name of the buffer PR's patch is washed into."
  (format "*nitpick-pr: %s*" (plist-get pr :label)))

(defun nitpick-pr--header-line (pr)
  "Return the header line of the buffer PR's patch is washed into.
No leading space: magit's own header line starts with one."
  (concat (plist-get pr :label) "  not checked out"))

(defun nitpick-pr--strip-prefixes ()
  "Drop the a/ and b/ path prefixes from the headers of the patch in the buffer.
magit's washer reads what `git diff --no-prefix\=' writes; a forge serves the
prefixes, and left in they make every file a rename of itself.  Headers only:
a patch of a patch has lines inside its hunks that look like headers."
  (goto-char (point-min))
  (while (re-search-forward "^diff --git " nil t)
    (beginning-of-line)
    (let* ((start (point))
           ;; A marker: every replacement below shortens the header it is the
           ;; end of.
           (end (copy-marker
                 (save-excursion
                   (forward-line 1)
                   (if (re-search-forward "^\\(?:@@\\|diff --git \\)" nil t)
                       (match-beginning 0)
                     (point-max))))))
      (save-restriction
        (narrow-to-region start end)
        (when (looking-at "diff --git a/\\(.*\\) b/\\1$")
          (replace-match "diff --git \\1 \\1"))
        (while (re-search-forward "^\\(---\\|\\+\\+\\+\\) [ab]/" nil t)
          (replace-match "\\1 "))
        (goto-char (point-min))
        (when (re-search-forward "^Binary files a/\\(.*\\) and b/\\(.*\\) differ$" nil t)
          (replace-match "Binary files \\1 and \\2 differ")))
      (goto-char end)
      (set-marker end nil))))

(defun nitpick-pr--insert (file)
  "Insert FILE at point, and wash it into magit's own diff sections.
The washer only ever reads the buffer in front of it, so a patch becomes the
sections `git diff' would have produced - which is what the pane narrows to."
  (let ((beg (point)))
    (goto-char (+ beg (cadr (insert-file-contents file))))
    (save-restriction
      (narrow-to-region beg (point))
      (nitpick-pr--strip-prefixes)
      (goto-char (point-min))
      (magit-diff-wash-diffs nil))))

(defun nitpick-pr-visit ()
  "Check the pull request out, and open the file the point is in.
`o' in the pane, asked for from the diff: a patch holds no files, so this is
what fetches them."
  (interactive)
  (let ((pr (or nitpick-pr--pr (user-error "Not a patch buffer")))
        (file (or (magit-file-at-point) (user-error "No file here"))))
    (nitpick-pr--check-out pr file
                           (lambda (root) (nitpick-tree--adopt root file)))))

(defun nitpick-pr-comment ()
  "Say why there is nothing to comment on yet.
A thread is anchored on the pull request's head commit and on the files it
names; a patch on its own carries neither."
  (interactive)
  (user-error "Not checked out yet: RET on a hunk does that, then comment"))

(defvar nitpick-pr-patch-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Remaps, because the keys themselves are bound in magit's section maps,
    ;; which are text properties and outrank any mode map here.
    (define-key map [remap nitpick-visit] #'nitpick-pr-visit)
    (define-key map [remap nitpick-visit-other] #'nitpick-pr-visit)
    (define-key map [remap nitpick-comment] #'nitpick-pr-comment)
    map)
  "Keymap of a patch buffer, on top of `magit-diff-mode-map'.")

(define-derived-mode nitpick-pr-patch-mode magit-diff-mode "Magit Patch"
  "Major mode for a diff washed from a patch rather than read from git.
A magit diff buffer in every other way; refreshing it re-washes the patch,
which is all a diff with no repository behind it can be refreshed from."
  :group 'nitpick)

(defconst nitpick-pr--definitions
  '(progn
     (defun nitpick-pr-patch-refresh-buffer ()
       "Wash this buffer's patch, again.
Magit's own refresh for `nitpick-pr-patch-mode': the mode's name is what
`magit-refresh-buffer' derives this one's from."
       (magit-set-header-line-format (nitpick-pr--header-line nitpick-pr--pr))
       (magit-insert-section (diffbuf)
         (nitpick-pr--insert nitpick-pr--file))))
  "Held as data until magit is loaded.
`magit-insert-section' is a macro and magit is deliberately out of scope when
this file is compiled, the same way `nitpick-tree' holds its treemacs node
types.  Everything the body calls is a function, compiled as usual.")

(defvar nitpick-pr--defined nil
  "Whether `nitpick-pr--definitions' has been evaluated.")

(defun nitpick-pr--define ()
  "Load magit's diff machinery and evaluate the definitions, once."
  (unless nitpick-pr--defined
    (require 'magit-diff)
    (eval nitpick-pr--definitions t)
    (setq nitpick-pr--defined t)))

(defun nitpick-pr--diff (pr &optional reread)
  "Return the buffer PR's patch is washed into, washing it if need be.
With REREAD the patch file is washed again, which is how a second read of the
same pull request reaches a buffer that is already up.  Never displayed here:
where the diff goes is the pane's business."
  (nitpick-pr--define)
  (let ((buffer (get-buffer (nitpick-pr--buffer-name pr))))
    (cond
     ((and buffer reread)
      (with-current-buffer buffer (magit-refresh-buffer))
      buffer)
     (buffer buffer)
     (t
      (with-current-buffer (get-buffer-create (nitpick-pr--buffer-name pr))
        ;; Not the repository the review was started from: magit would send
        ;; every git call the washer makes into a tree the patch is not of.
        (setq default-directory (nitpick-pr--directory))
        (nitpick-pr-patch-mode)
        (setq-local nitpick-pr--pr pr
                    nitpick-pr--file (nitpick-pr--patch-file pr))
        (magit-refresh-buffer t)
        (current-buffer))))))

;;;; Checking it out

(defun nitpick-pr--git-pr ()
  "Return the usable `git pr' executable, or signal a user error."
  (or (if (file-name-absolute-p nitpick-pr-git-pr-executable)
          (and (file-executable-p nitpick-pr-git-pr-executable)
               nitpick-pr-git-pr-executable)
        (executable-find nitpick-pr-git-pr-executable))
      (user-error "`git pr' is not available (see `nitpick-pr-git-pr-executable')")))

(defun nitpick-pr--errors (label)
  "Return the buffer `git pr\=' writes its progress for LABEL into.
One per pull request: a prefetch for the one just opened must not erase what
the one before it is still writing."
  (get-buffer-create (format " *nitpick-pr %s*" label)))

(defun nitpick-pr--tail (buffer separators)
  "Return the last non-empty field of BUFFER, split on SEPARATORS.
Git writes a line per failure and a `\\r\='-separated chunk per percent, so one
read answers both what went wrong and how far it got."
  (and (buffer-live-p buffer)
       (with-current-buffer buffer
         (car (last (split-string (buffer-string) separators t "[ \t\n\r]+"))))))

(defun nitpick-pr--complaint (buffer)
  "Return the last line BUFFER holds, which is why `git pr\=' failed.
That there is no clone of the repository the URL names, most of the time, and
not something to go looking in a buffer for."
  (nitpick-pr--tail buffer "\n"))

(defun nitpick-pr--progress (buffer)
  "Return how far BUFFER says `git pr\=' has got, or nil."
  (nitpick-pr--tail buffer "[\r\n]"))

(defun nitpick-pr--cloned-p (buffer)
  "Whether BUFFER says a clone was made rather than one found.
`git pr\=' says so itself before it starts.  Nothing is cloned when the
repository is already somewhere it looks, and reporting one then would be a
lie."
  (and (buffer-live-p buffer)
       (with-current-buffer buffer
         (save-excursion
           (goto-char (point-min))
           (and (search-forward "git pr: cloning " nil t) t)))))

(defun nitpick-pr--worktree (text)
  "Return the worktree `git pr\=' printed in TEXT, or nil.
The last line of it: the path is the last thing printed, and only on stdout."
  (let ((path (car (last (split-string text "\n" t)))))
    (and path (file-directory-p path) path)))

(defun nitpick-pr--environment ()
  "Return the environment `git pr\=' is run in.
`nitpick-pr-clone-directory\=' as GIT_PR_CLONE_ROOT, and only when it is set:
the default is `git pr\='s to name, so it is named in one place."
  (if nitpick-pr-clone-directory
      (cons (format "GIT_PR_CLONE_ROOT=%s"
                    (expand-file-name nitpick-pr-clone-directory))
            process-environment)
    process-environment))

(defconst nitpick-pr--phases '((clone . "cloning") (checkout . "checking out"))
  "What to call each phase of the work in a message.")

(defun nitpick-pr--flags (phase)
  "Return the `git pr\=' flags a PHASE job runs with.
A `clone\=' job asks for the clone and nothing else - no PR fetch, no
worktree, no session, so a pull request only read leaves none behind.  A
`checkout\=' job makes the worktree, and may clone first: once cloning is
allowed at all, a prefetch that failed must not leave the visit stranded."
  (pcase phase
    ('clone '("--clone-only"))
    (_ (and nitpick-pr-clone '("--clone")))))

;;;; The jobs that make a worktree

(defvar nitpick-pr--jobs nil
  "The `git pr\=' jobs in flight, as an alist of label to plist.
Keys: `:process\=', `:phase\=' (`clone\=' or `checkout\='), `:errors\=' the
buffer its progress goes to, `:pending\=' what to run once a worktree exists,
and `:file\=' what that opens.  One job per pull request, so a second `o\='
joins the one already running instead of starting another.")

(defun nitpick-pr--job (label)
  "Return LABEL's job while it runs, forgetting it once it has stopped."
  (let ((job (cdr (assoc label nitpick-pr--jobs))))
    (cond
     ((null job) nil)
     ((process-live-p (plist-get job :process)) job)
     (t (setq nitpick-pr--jobs (assoc-delete-all label nitpick-pr--jobs))
        nil))))

(defun nitpick-pr--start (pr phase &optional file callback)
  "Run `git pr\=' for PR as a PHASE job, and remember it as that PR's.
CALLBACK is handed the worktree once there is one, and FILE is what it opens
- neither of which a clone started by a prefetch has yet.  Asynchronous: it
fetches, and there is no reason for Emacs to wait on the network."
  (let* ((program (nitpick-pr--git-pr))
         (label (plist-get pr :label))
         (errors (nitpick-pr--errors label))
         (out (generate-new-buffer (format " *nitpick-pr out %s*" label)))
         (default-directory (plist-get pr :dir))
         (process-environment (nitpick-pr--environment)))
    (with-current-buffer errors (erase-buffer))
    (let ((process
           (make-process
            :name "nitpick-pr"
            :command (append (list program)
                             (nitpick-pr--flags phase)
                             (list (plist-get pr :ref)))
            :buffer out
            :stderr errors
            :connection-type 'pipe
            :sentinel
            (lambda (process _event)
              (when (memq (process-status process) '(exit signal))
                ;; The stderr pipe is a process of its own, and what it holds
                ;; can still be in flight when this one exits.
                (let ((pipe (get-buffer-process errors)))
                  (when pipe (accept-process-output pipe 0.2)))
                (let ((code (process-exit-status process))
                      (text (with-current-buffer out (buffer-string))))
                  (kill-buffer out)
                  (nitpick-pr--land pr code text)))))))
      (setq nitpick-pr--jobs
            (cons (cons label (list :process process :phase phase
                                    :errors errors :pending callback
                                    :file file))
                  (assoc-delete-all label nitpick-pr--jobs)))
      process)))

(defun nitpick-pr--land (pr code text)
  "Act on the job that has just finished for PR: its exit CODE and stdout TEXT.
A clone that something was waiting for starts the checkout itself, so the
visit that asked for the files carries on where it left off."
  (let* ((label (plist-get pr :label))
         (job (cdr (assoc label nitpick-pr--jobs)))
         (phase (plist-get job :phase))
         (errors (plist-get job :errors))
         (pending (plist-get job :pending))
         (file (plist-get job :file))
         (path (nitpick-pr--worktree text)))
    (setq nitpick-pr--jobs (assoc-delete-all label nitpick-pr--jobs))
    (cond
     ((/= code 0)
      (message "nitpick-pr: %s"
               (or (nitpick-pr--complaint errors)
                   (format "git pr failed for %s - see %s"
                           label (buffer-name errors)))))
     ((eq phase 'clone)
      (when (nitpick-pr--cloned-p errors)
        (message "nitpick-pr: cloned %s into %s" label (string-trim text)))
      (when pending
        (nitpick-pr--start pr 'checkout file pending)))
     ((null path)
      (message "nitpick-pr: git pr printed no worktree for %s" label))
     (t (funcall pending path)))))

(defun nitpick-pr--join (job label file callback)
  "Have JOB open FILE with CALLBACK once it lands, and say where it has got to.
What `o\=' does to a clone a prefetch already started: nothing is run twice,
and nothing is waited for."
  (plist-put job :pending callback)
  (plist-put job :file file)
  (let ((progress (nitpick-pr--progress (plist-get job :errors))))
    (message "nitpick-pr: %s %s%s - will open %s when it lands"
             (alist-get (plist-get job :phase) nitpick-pr--phases)
             label
             (if progress (format " - %s" progress) "")
             file)))

(defun nitpick-pr--check-out (pr file callback)
  "Have PR checked out, then call CALLBACK with the worktree it landed in.
FILE is the file being opened, for the message a joined job prints.  A job
already in flight for this pull request is joined rather than doubled -
usually the clone a prefetch started as the pane opened."
  (let* ((label (plist-get pr :label))
         (job (nitpick-pr--job label)))
    (if job
        (nitpick-pr--join job label file callback)
      (message "nitpick-pr: checking out %s..." label)
      (nitpick-pr--start pr 'checkout file callback))))

(defun nitpick-pr--prefetch (pr)
  "Start the clone PR may need, when `nitpick-pr-clone\=' asks for it early.
Quietly, and without ever standing in the way of reading: nothing is cloned
when the repository is already there, and a `git pr\=' that is not installed
must not stop a pull request from opening."
  (when (and (eq nitpick-pr-clone 'prefetch)
             (not (nitpick-pr--job (plist-get pr :label))))
    (condition-case err
        (nitpick-pr--start pr 'clone)
      (error (message "nitpick-pr: not prefetching %s - %s"
                      (plist-get pr :label) (error-message-string err))))))

;;;; The command

(defvar nitpick-pr--history nil
  "Pull requests `nitpick-pr' has been asked for.")

(defun nitpick-pr--patch (pr file)
  "Return what the pane needs to drive PR's patch in FILE."
  (list :label (plist-get pr :label)
        :file file
        :diff (lambda () (nitpick-pr--diff pr))
        :check-out (lambda (file callback)
                     (nitpick-pr--check-out pr file callback))))

(defun nitpick-pr--root (pr)
  "Return the directory the pane folds PR's paths under.
No such directory, and nothing is written there: a patch is not a checkout,
and the pane only needs an absolute prefix to key its nodes by.  Named after
the pull request, so two of them cannot collide."
  (file-name-as-directory
   (expand-file-name (string-replace "/" "-" (plist-get pr :label))
                     (nitpick-pr--directory))))

;;;###autoload
(defun nitpick-pr (spec)
  "Review the pull request SPEC names, without checking it out.

SPEC is its URL, `owner/repo#number', or a number, which means one of the
repository at hand.  The forge's own diff of it opens in the pane
`nitpick-tree' uses, so the review reads by walking the files it changed.

Nothing is cloned or fetched: one `gh pr diff' is the whole cost.  The files
themselves arrive when one is asked for - RET on a hunk, or `o' in the pane -
which checks the pull request out in a sibling worktree and re-reads the pane
from git there, where the review is the full one.

Called again for the same pull request it asks the forge again, so this is
also how a pane goes to the head the PR has now; `g' in the pane re-reads the
patch already fetched."
  (interactive (list (read-string "Review pull request: " nil 'nitpick-pr--history)))
  (let* ((pr (nitpick-pr--parse spec))
         ;; Before the patch is asked for, so the clone and the diff are
         ;; fetched at the same time rather than one after the other.
         (_ (nitpick-pr--prefetch pr))
         (file (nitpick-pr--read pr)))
    (nitpick-pr--diff pr 'reread)
    (nitpick-tree (nitpick-pr--root pr) nil (nitpick-pr--patch pr file))))

(provide 'nitpick-pr)

;;; nitpick-pr.el ends here
