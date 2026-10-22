# revu

Batched pull request reviews from Emacs, anchored on the files on disk.

The overlay adds `revu` to the Emacs package scope, and the `emacs` home
module installs it. Comment on the line at point, batch the drafts into a
server-side pending review, submit them together with a verdict.

Drafts live on the forge from the moment they are added, so they survive a crash
and stay submittable from the web UI. GitHub via the `gh` CLI is the only backend
today; the public names are backend-neutral (see dotless #99).

## Commands

| Command | What it does |
| --- | --- |
| `revu-comment` | Draft a comment on the current line or region |
| `revu-list` | List the pending review's drafts, flagging outdated ones |
| `revu-submit` | Publish the drafts with COMMENT / APPROVE / REQUEST_CHANGES |
| `revu-refresh` | Resync the worktree to the PR head after the author pushes |
| `revu-diff-hl-set-base` | Point diff-hl at the PR base, so gutters show the PR's changes |
| `revu-diff-hl-toggle` | Turn the PR-base diff on the worktree on or off |

## Binding

Bind them yourself; `revu-prefix-map` holds `c`, `l`, `s`, `f`, `h`.
Enable `revu-forge-mode` to route Forge's approve / request-changes through
the batch submitter.

```elisp
(require 'revu)
(revu-forge-mode 1)
(map! :leader :prefix "g" (:prefix ("V" . "review")
       :desc "Comment on PR line(s)" :m "c" #'revu-comment
       :desc "List pending review"   :m "l" #'revu-list
       :desc "Submit review"         :m "s" #'revu-submit
       :desc "Refresh to PR head"    :m "f" #'revu-refresh
       :desc "Toggle the PR diff"    :m "h" #'revu-diff-hl-toggle))
```

## Whole-line highlighting

`revu-diff-hl-set-base` points diff-hl at the PR base, so the fringe marks
every line the PR touched. `revu-diff-hl-line-mode` additionally paints those
lines with a background, which reads better than fringe marks alone on a big
diff. It is turned on by `revu-diff-hl-set-base`; set
`revu-diff-hl-line-highlight` to nil to keep the fringe only.

`revu-diff-hl-toggle` flips the whole thing, both halves at once: the
reference revision and the line painting. Checking out a PR worktree turns it
on, so the toggle is mostly for switching back and forth while reading. The
base branch is remembered per worktree, so only the first turn-on in a
worktree asks the forge for it.

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
  `revu-diff-hl-line-faces` to override.
- `revu-diff-hl-line-priority` is -60, below `hl-line`'s -50, so the cursor
  line keeps its own colour. Raise it above -50 to let the diff colour win.

## Tests

ERT, run in `checkPhase` on every build:

```
nix build .#emacsPackages.revu
```

To run them against a checkout:

```
emacs --batch -L . -l ert -l revu.el -l test/revu-test.el \
      -f ert-run-tests-batch-and-exit
```

The suite is hermetic: no network, no `gh`, no magit. `test/revu-test.el`
replaces the forge with stubs that record what would have been sent and reply
with canned JSON.
