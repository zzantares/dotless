# nitpick

Batched pull request reviews from Emacs, anchored on the files on disk.

The overlay adds `nitpick` to the Emacs package scope, and the `emacs` home
module installs it. Comment on the line at point, batch the drafts into a
server-side pending review, submit them together with a verdict.

Drafts live on the forge from the moment they are added, so they survive a crash
and stay submittable from the web UI. GitHub via the `gh` CLI is the only backend
today; the public names are backend-neutral (see dotless #99).

## Commands

| Command | What it does |
| --- | --- |
| `nitpick-comment` | Draft a comment on the current line or region |
| `nitpick-list` | List the pending review's drafts, flagging outdated ones |
| `nitpick-submit` | Publish the drafts with COMMENT / APPROVE / REQUEST_CHANGES |
| `nitpick-refresh` | Resync the worktree to the PR head after the author pushes |
| `nitpick-diff-hl-set-base` | Diff the project against a revision you pick, instead of its checkout |
| `nitpick-diff-hl-line-mode` | Paint the changed lines, not only the fringe |
| `nitpick-tree` | Side pane of the files the review changed, and nothing else |

## Binding

`nitpick-mode` is the default bindings, opt-in: it puts `nitpick-prefix-map` (`c`,
`l`, `s`, `f`, `b`, `H`, `t`) on `nitpick-keymap-prefix`, which defaults to `C-c v`. So
`C-c v c` comments, `C-c v s` submits. Enable `nitpick-forge-mode` as well to
route Forge's approve / request-changes through the batch submitter.

```elisp
(require 'nitpick)
(nitpick-mode 1)
(nitpick-forge-mode 1)
```

Set `nitpick-keymap-prefix` through Customize (or `setopt`) to move the prefix;
the old one is unbound for you. Set it to nil, or leave `nitpick-mode` off, and
nothing is bound - then bind `nitpick-prefix-map` wherever you like:

```elisp
(map! :leader :prefix "g" (:prefix ("V" . "review")
       :desc "Comment on PR line(s)" :m "c" #'nitpick-comment
       :desc "List pending review"   :m "l" #'nitpick-list
       :desc "Submit review"         :m "s" #'nitpick-submit
       :desc "Refresh to PR head"    :m "f" #'nitpick-refresh
       :desc "Set the diff base"     :m "b" #'nitpick-diff-hl-set-base
       :desc "Paint changed lines"   :m "H" #'nitpick-diff-hl-line-mode
       :desc "Tree of changed files" :m "t" #'nitpick-tree))
```

## The changed-file pane

`nitpick-tree` opens a treemacs side pane holding only the files that differ
from the revision under review, nested by directory - what diffnav draws next
to its diff. Each line carries the file's status marker and its line counts,
and `RET` opens the real file, where diff-hl has already painted the same
revision's changes. A prefix argument keeps the focus in the pane, so a review
can be opened file by file without leaving it.

The revision is the one this worktree last picked, through
`nitpick-diff-hl-set-base` or through checking out a PR's worktree, so the pane
lists exactly the files diff-hl is painting. `C-u` asks for another, and is
also how the pane is pointed somewhere new.

Calling it again re-renders, and so is the refresh; committing, staging and
unstaging redraw it too, because git gives no notification of its own and a
pane of a diff goes stale exactly when the diff does.

What a line says:

- `M` is left off, since most of a review is modifications and the counts
  already say the file changed. `A`, `D`, `R`, `?` get their letter.
- A rename names where it came from: the marker says it moved, only the old
  path says what it was.
- A binary file says `bin`. git diffs it without ever saying by how much.
- An untracked file is listed with `?` and no counts. It is not part of
  `git diff`, so the forge will not show it either - but a file you forgot to
  add is the one most worth seeing before you submit. Set
  `nitpick-tree-show-untracked` to nil for only what the forge sees.
- A chain of directories holding nothing but each other is drawn as one line
  (`nix/pkgs/emacs`). treemacs does this for real directories through
  `treemacs-collapse-dirs`; an extension has to do its own, so this one has
  `nitpick-tree-collapse-dirs`.

A deleted file has nothing on disk to open, so it opens from the revision
instead - the read-only blob magit would show.

treemacs is needed at run time only, and the command loads it. Its extension
API is macros, which a build without treemacs in scope could not compile -
and putting treemacs in scope would shadow the copy the user's Emacs installs.
So the node-type declaration is held as data and evaluated the first time the
command runs, the same way nitpick waits for diff-hl before advising it.
Everything that declaration calls is an ordinary byte-compiled function.

One pane, re-rendered per project, the way treemacs shows one tree. It sits in
slot 1 of treemacs' own side, so it sits alongside a treemacs tree rather than
replacing it.

## Whole-line highlighting

Two decisions, one each:

- **What is compared.** `nitpick-diff-hl-set-base` asks for a revision and
  diffs the project against it: a local branch, a remote-tracking ref like
  `origin/master`, a tag, a sha. It is used as picked, so `master` and
  `origin/master` are different answers. Pick `HEAD` for the usual view of
  your own uncommitted edits. Checking out a PR worktree sets it to the PR's
  base as the remote has it, and each worktree's last answer is what the
  prompt suggests next time.

  The comparison is `git diff <revision>`, against its tip, so it agrees with
  magit's diff of the same revision. A trailing `...` asks for the merge base
  instead, as in git: `master` is every line that differs from master now,
  `master...` is only what this branch changed since it left master - the
  forge's "Files changed". diff-hl is pointed at the revision rather than a
  resolved sha, so a branch that moves is followed.
- **How it is drawn.** `nitpick-diff-hl-line-mode` paints the changed lines
  with a background, which reads better than fringe marks alone on a big diff.
  It is global and independent: the command above never touches it.

There is no on and off, because a base is not a state to be in - it is a
revision, and `HEAD` is one of the revisions you can pick. So nitpick keeps no
belief about whether a view is active, and nothing of its own can disagree
with what diff-hl is showing. A reference you set yourself with
`diff-hl-set-reference-rev` is equally yours; nitpick neither reads it nor
clears it.

What diff-hl draws with a base other than `HEAD` is two sets of hunks: the
commits between that base and HEAD, drawn through
`diff-hl-highlight-reference-function`, and your uncommitted edits on top,
drawn the usual way. One base, two sets - the edit cue never goes away.

The mode swaps both of diff-hl's highlight slots - `diff-hl-highlight-function` for
working-tree changes and `diff-hl-highlight-reference-function` for changes
against the reference revision. A PR's own lines come through the second, so
swapping only the first leaves them bare. Whatever the slots held still runs,
so the fringe or margin marks stay, and the mode puts them back when off.

Three things shape the result:

- The faces must set `:extend t`, or the background stops at end-of-line and
  the diff block looks like a bar chart of line lengths.
- `delete` lines are deliberately not painted: diff-hl's overlay for a removal
  sits on the line *after* the removed text, which the PR never touched. The
  fringe mark still shows it. Add a `delete` entry to
  `nitpick-diff-hl-line-faces` to override.
- `nitpick-diff-hl-line-priority` is -60, below `hl-line`'s -50, so the cursor
  line keeps its own colour. Raise it above -50 to let the diff colour win.

## Tests

ERT, run in `checkPhase` on every build:

```
nix build .#nitpick
```

To run them against a checkout:

```
emacs --batch -L . -l ert -l nitpick.el -l test/nitpick-test.el \
      -f ert-run-tests-batch-and-exit
```

The suite is hermetic: no network, no `gh`, no magit. `test/nitpick-test.el`
replaces the forge with stubs that record what would have been sent and reply
with canned JSON.
