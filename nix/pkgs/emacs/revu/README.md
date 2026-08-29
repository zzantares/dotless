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

## Binding

Bind them yourself; `revu-prefix-map` holds `c`, `l`, `s`, `f`. Enable
`revu-forge-mode` to route Forge's approve / request-changes through the
batch submitter.

```elisp
(require 'revu)
(revu-forge-mode 1)
(map! :leader :prefix "g" (:prefix ("V" . "review")
       :desc "Comment on PR line(s)" :m "c" #'revu-comment
       :desc "List pending review"   :m "l" #'revu-list
       :desc "Submit review"         :m "s" #'revu-submit
       :desc "Refresh to PR head"    :m "f" #'revu-refresh))
```

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
