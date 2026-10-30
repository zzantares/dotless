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

## Binding

`nitpick-mode` is the default bindings, opt-in: it puts `nitpick-prefix-map` (`c`,
`l`, `s`, `f`, `b`, `H`) on `nitpick-keymap-prefix`, which defaults to `C-c v`. So
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
       :desc "Paint changed lines"   :m "H" #'nitpick-diff-hl-line-mode))
```

## Whole-line highlighting

Two decisions, one each:

- **What is compared.** `nitpick-diff-hl-set-base` asks for a revision and
  diffs the project against it: a local branch, a remote-tracking ref like
  `origin/master`, a tag, a sha. It is used as picked, so `master` and
  `origin/master` are different answers. Pick `HEAD` for the usual view of
  your own uncommitted edits. Checking out a PR worktree sets it to the PR's
  base as the remote has it, and each worktree's last answer is what the
  prompt suggests next time.
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
nix build .#emacsPackages.nitpick
```

To run them against a checkout:

```
emacs --batch -L . -l ert -l nitpick.el -l test/nitpick-test.el \
      -f ert-run-tests-batch-and-exit
```

The suite is hermetic: no network, no `gh`, no magit. `test/nitpick-test.el`
replaces the forge with stubs that record what would have been sent and reply
with canned JSON.
