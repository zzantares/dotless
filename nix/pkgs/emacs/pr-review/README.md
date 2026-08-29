# pr-review

Batched pull request reviews from Emacs, anchored on the files on disk.

The overlay adds `pr-review` to the Emacs package scope, and the `emacs` home
module installs it. Comment on the line at point, batch the drafts into a
server-side pending review, submit them together with a verdict.

Drafts live on the forge from the moment they are added, so they survive a crash
and stay submittable from the web UI. GitHub via the `gh` CLI is the only backend
today; the public names are backend-neutral (see dotless #99).

## Commands

| Command | What it does |
| --- | --- |
| `pr-review-comment` | Draft a comment on the current line or region |
| `pr-review-list` | List the pending review's drafts, flagging outdated ones |
| `pr-review-submit` | Publish the drafts with COMMENT / APPROVE / REQUEST_CHANGES |
| `pr-review-refresh` | Resync the worktree to the PR head after the author pushes |
| `pr-review-diff-hl-set-base` | Point diff-hl at the PR base, so gutters show the PR's changes |

## Binding

Bind them yourself; `pr-review-prefix-map` holds `c`, `l`, `s`, `f`. Enable
`pr-review-forge-mode` to route Forge's approve / request-changes through the
batch submitter.

```elisp
(require 'pr-review)
(pr-review-forge-mode 1)
(map! :leader :prefix "g" (:prefix ("V" . "review")
       :desc "Comment on PR line(s)" :m "c" #'pr-review-comment
       :desc "List pending review"   :m "l" #'pr-review-list
       :desc "Submit review"         :m "s" #'pr-review-submit
       :desc "Refresh to PR head"    :m "f" #'pr-review-refresh))
```

## Tests

ERT, run in `checkPhase` on every build:

```
nix build .#emacsPackages.pr-review
```

To run them against a checkout:

```
emacs --batch -L . -l ert -l pr-review.el -l test/pr-review-test.el \
      -f ert-run-tests-batch-and-exit
```

The suite is hermetic: no network, no `gh`, no magit. `test/pr-review-test.el`
replaces the forge with stubs that record what would have been sent and reply
with canned JSON.
