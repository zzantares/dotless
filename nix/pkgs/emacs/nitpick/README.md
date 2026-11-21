# nitpick

Batched pull request reviews from Emacs, anchored on the files on disk.

The overlay adds `nitpick` to the Emacs package scope, and the `emacs` home
module installs it. Comment on the line or the diff hunk at point, batch the
drafts into a server-side pending review, submit them together with a verdict.

Drafts live on the forge from the moment they are added, so they survive a crash
and stay submittable from the web UI. GitHub via the `gh` CLI is the only backend
today; the public names are backend-neutral (see dotless #99).

## Commands

| Command | What it does |
| --- | --- |
| `nitpick-comment` | Draft a comment on the line, region, or diff hunk at point |
| `nitpick-list` | List the pending review's drafts, flagging outdated ones |
| `nitpick-submit` | Publish the drafts with COMMENT / APPROVE / REQUEST_CHANGES |
| `nitpick-refresh` | Resync the worktree to the PR head after the author pushes |
| `nitpick-diff-hl-set-base` | Diff the project against a revision you pick, instead of its checkout |
| `nitpick-diff-hl-line-mode` | Paint the changed lines, not only the fringe |
| `nitpick-tree` | Toggle the review: the pane of changed files, and the diff beside it |
| `nitpick-pr` | Read a pull request in that pane without checking it out |
| `nitpick-tree-visit-diff` | Reveal the line at point in the diff (`d` in the pane) |
| `nitpick-tree-toggle-follow` | Stop or resume the diff following the point (`f` in the pane) |
| `nitpick-tree-toggle-narrow` | Narrow the diff to the line at point, or widen it (`N` in the pane) |
| `nitpick-diff-buffer-file` | The same diff for the file being visited, from anywhere |
| `nitpick-visit` | Open the file at point as the version the line belongs to (`RET`) |
| `nitpick-visit-other` | Open it as the other version (`S-RET`) |
| `nitpick-visit-pick` | Open it as a version picked by name (`C-u` on either key) |
| `nitpick-diff-visit-base-mode` | Let magit name the base side of a bare-revision diff |

## Binding

`nitpick-mode` is the default bindings, opt-in: it puts `nitpick-prefix-map` (`c`,
`l`, `s`, `f`, `b`, `H`, `t`, `d`) on `nitpick-keymap-prefix`, which defaults to `C-c v`. So
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
       :desc "Tree of changed files" :m "t" #'nitpick-tree
       :desc "Diff file vs base"     :m "d" #'nitpick-diff-buffer-file))
```

## What a comment lands on

`nitpick-comment` reads its target from where it is called:

- In a **file buffer**, the line at point, or the lines a region covers.
- In a **magit diff buffer** - `nitpick-diff-buffer-file`, the pane's `d`, any
  `magit-diff` - the hunk at point, or the part of it a region covers.

A hunk comments on its added lines, not on the context around them, so the
range the forge shows is the change itself. A hunk with only removals is
commented on the base side (`LEFT`), which is the only side those lines have;
a selection of nothing but context lines anchors on the context, which the
forge accepts because it is inside the diff.

Magit's status buffer is left out on purpose: its hunks are the worktree's
changes, not the PR's. Revision buffers too - a commit's new-side line numbers
are the PR head's only for the last commit on the branch. And a file with
uncommitted changes is refused, because the new side of the diff is the
worktree: edit it and the numbers stop being the PR's.

## The diff navigator

`nitpick-tree` opens a treemacs side pane holding only the files that differ
from the revision under review, nested by directory, and the diff of that
range beside it - what diffnav draws. Each line carries the file's status
marker and its line counts.

Moving in the pane narrows the diff to the file at point, or to the subtree of
the directory at point, so a review reads by walking the pane and a file
outside what the point covers is not on screen at all. `nitpick-tree-narrow`
turns that off and `N` toggles it, which is how the whole range is read
continuously. `nitpick-tree-follow` stops the diff following the point at all,
`f` toggles that, and `d` is then how a diff is asked for.

Keys in the pane: `RET` hands the point to the diff, where magit's own keys
read it and `nitpick-comment` comments on it. `o` opens the real file, where
diff-hl has already painted the same revision's changes; a prefix argument
keeps the focus in the pane.

Opening takes the frame and `q` gives it back, the way magit's status buffer
does - the pane and its diff want the frame to themselves. `nitpick-tree-full-frame`
turns that off.

The revision is the one this worktree last picked, through
`nitpick-diff-hl-set-base` or through checking out a PR's worktree, and failing
that the nearest ancestor branch (below). `C-u` asks for another, and is also
how the pane is pointed somewhere new.

A worktree with no base yet also gets pointed at that revision, so the files
opened from the pane paint the same changes the pane lists - one keystroke
instead of `nitpick-diff-hl-set-base` first. A base already picked is left
alone, and `nitpick-tree-set-base` turns this off.

Those changes are drawn as whole lines, not fringe marks alone: opening the
pane turns on `nitpick-diff-hl-line-mode`, and a file opened from it gets
`diff-hl-mode` buffer-locally if it was off, since otherwise there is nothing
to paint. `nitpick-tree-paint-lines` turns both off. Nothing happens without
diff-hl loaded - the line mode reads its highlight slots as it starts.

Calling it again closes the pane and undoes the painting it turned on - one
key for both directions. A painting you turned on yourself with
`nitpick-diff-hl-line-mode` is yours and survives; so does the base, which is
the revision under review rather than a way of drawing it. The buffer goes
with the window, since it holds a diff read once.

`C-u` always opens, so it is also how an open pane is pointed somewhere new,
and `q` in the pane closes it the same way the toggle does - treemacs' own `q`
would bury it and leave the painting on.

`r` re-reads the diff; committing, staging and unstaging redraw it too,
because git gives no notification of its own and a pane of a diff goes stale
exactly when the diff does.

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

### Two keys: now and before

A diff position names a file and a line on two sides. The keystroke names
which side to open - nothing is inferred from where the cursor sits:

- **`RET`** (`nitpick-visit`) opens the version the line at point belongs to.
- **`S-RET`** (`nitpick-visit-other`) opens the other one.
- In the pane the same pair is **`o`** and **`O`**.

So the pair is total: no hunk shape can put a version out of reach, which is
what `magit-diff-visit-file` alone cannot promise - on a hunk of nothing but
additions it has no removed line to stand on, and its escape hatch
(`magit-diff-visit-worktree-file`) is the worktree rather than the other side.

| Where the point is | `RET` / `o` | `S-RET` / `O` |
| --- | --- | --- |
| Pane, file node | worktree, at its first change | base blob, at its first change |
| Pane, deleted file | base blob | base blob |
| Pane, new or untracked file | worktree | worktree |
| Pane, directory | expand / collapse | nothing to open |
| Diff, file heading | worktree, first change | base blob, first change |
| Diff, context line | worktree, that line | base blob, same line |
| Diff, added line | worktree, that line | base blob, the insertion point |
| Diff, removed line | base blob, that line | worktree, the line now there |
| Diff, hunk of only deletions | base blob, that line | worktree, the removal point |
| Diff, hunk of only additions | worktree, that line | base blob, the insertion point |
| Combined diff, context line | worktree, that line | the base of the conflict |
| Combined diff, a parent's line | that parent, its own line | worktree, with the markers |
| Combined diff, marker line | worktree, that line | the base of the conflict |
| Untracked preview | the file | the file |

Two rules behind the table:

- **A line belongs to the version its column says it does.** An added line is
  in the worktree, a removed one in the base, a context line in both - where
  the worktree wins, since that is the file you edit. A combined diff carries
  one column per parent, and a line is the other side of the parent whose
  column differs from the rest.
- **A side the file has no version in opens the side it has, and says so.**
  The base of a file this review added, the worktree of one it deleted:
  the key still opens something, and the echo area says which and why.

Outside a hunk - a file heading, a pane node - no line belongs anywhere, so
both keys land on the file's first change.

With a prefix argument either key picks the version by name instead, which is
the way to the ones no line belongs to: the base of a conflict, or the parent a
line is not marked against.

### Two views of the same change

The diff is what the pane navigates; `o` opens a file. They answer different
questions and neither replaces the other:

- The **file** is where LSP works, where jump-to-definition and the type
  errors live, and where you fix what the review turns up. Both views take a
  comment; only the file takes one on a line the diff never showed.
- The **file** opens in the window last used, reusing the one already showing
  it if there is one - never a split. `display-buffer` splits here, because a
  side window can show nothing but the pane, so it makes room rather than
  reuse.
- The **diff** is the reading view - before and after together, removals as
  text, unchanged context folded away. A directory reveals its subtree, so a
  collapsed `nix/pkgs/emacs` reads as one diff.

One magit buffer holds the whole range - `git diff` against the pane's own
revision, with your saved magit diff arguments - and a node is revealed by
narrowing to the span its sections cover. So following the point costs a
`narrow-to-region` and nothing is spawned per keystroke. Widened with `N`, the
same buffer reads continuously: the file before and the file after are a
scroll away.

### Narrowing, and what diffnav does instead

git orders a diff by path, so a directory's files are one run of the file
sections in that buffer - which is the whole trick: the span from the first to
the last is what the window is narrowed to.

diffnav arrives at the same picture from the other end. It parses the diff
once into file objects, sorts them itself, hangs them off the tree, and for a
directory re-serializes that subtree's objects back into patch text and runs
`delta` over it again, caching the result per node. Ordering never comes into
it, and nothing is narrowed.

The cost of leaning on the order is rename detection, which can place a file
outside its own directory's run. Emacs narrows to one region and a hole in it
would hide a file the review has to read, so a subtree the diff holds out of
order is scrolled to instead, exactly as it was before narrowing existed.

An untracked file is in no range diff, since git holds no version of it to
compare against, so it gets a `diff-mode` buffer of its own: `git diff
--no-index` against `/dev/null`, all additions.

`nitpick-diff-buffer-file` is the same diff for the file being visited rather
than the one at point, so a file reached any other way still reads as a diff.
diff-hl's own `diff-hl-diff-reference-goto-hunk` compares the same two things
and renders a `vc-diff` buffer instead of a magit one.

### What the two keys stand on

Three magit details, each measured rather than assumed:

- `magit-diff-visit--sides` works the sides out of the range its buffer holds,
  and `magit-split-range` answers nil for a range with no separator in it - a
  bare revision against the worktree, which is every diff nitpick opens. Both
  sides then came out as the worktree. `nitpick-diff-visit-base-mode` fills in
  that one pair and leaves every shape magit resolves itself alone.
- A combined diff keeps its per-parent ranges in the hunk's `from-range` slot
  and leaves `from-ranges` - which magit's own line counting reads - empty, so
  the per-parent line numbers are counted here instead.
- `magit-find-file-noselect` answers an index stage with an empty buffer: it
  inserts by the revision of the buffer it made, and a stage is not one. A
  conflict's three sides are read directly, into read-only buffers named the
  way magit names a blob's.

`r` re-reads the diff, and `g` does too outside evil, in place of treemacs'
`treemacs-refresh` - which redraws the nodes the pane already holds and
reports success without asking git anything. Fine for a file tree, wrong for a
snapshot of a diff. `g` is left alone under evil, where it is a prefix and
taking it would cost `gg`.

`d` is `treemacs-delete-file` in a file tree, and dead under evil, whose
motion state binds every plain letter to `undefined`. The pane shadows it
either way, through `nitpick-tree-mode-map` - which also means evil users need
an auxiliary map for the key to be seen at all:

```elisp
(after! treemacs-evil
  (evil-define-key 'treemacs nitpick-tree-mode-map
    (kbd "d") #'nitpick-tree-visit-diff
    (kbd "o") #'nitpick-tree-visit
    (kbd "O") #'nitpick-tree-visit-other
    (kbd "f") #'nitpick-tree-toggle-follow
    (kbd "N") #'nitpick-tree-toggle-narrow
    (kbd "r") #'nitpick-tree-refresh))
```

`o` is treemacs' prefix for opening a node in a split. Here the other window
is the diff, so the pane takes `o` for the file itself. `N` rather than `n`
for the narrowing toggle: `n` is `treemacs-next-line`, which is how the pane
is walked.

The diff's own two keys go in magit's section maps, which are text-property
keymaps and so outrank any minor mode's - there is nowhere else to say it:

```elisp
(defun my/nitpick-visit-keys ()
  (dolist (map (list magit-file-section-map magit-hunk-section-map))
    (define-key map (kbd "RET") #'nitpick-visit)
    (define-key map (kbd "S-<return>") #'nitpick-visit-other)))
(after! magit (my/nitpick-visit-keys))
(after! evil-collection-magit (my/nitpick-visit-keys))
```

Twice, because `evil-collection-magit` points `RET` at
`magit-diff-visit-worktree-file` when it loads, and whichever of the two loads
last has the say.

treemacs is needed at run time only, and the command loads it. Its extension
API is macros, which a build without treemacs in scope could not compile -
and putting treemacs in scope would shadow the copy the user's Emacs installs.
So the node-type declaration is held as data and evaluated the first time the
command runs, the same way nitpick waits for diff-hl before advising it.
Everything that declaration calls is an ordinary byte-compiled function.

One pane, re-rendered per project, the way treemacs shows one tree. It sits in
slot 1 of treemacs' own side, so it sits alongside a treemacs tree rather than
replacing it.

## Reading a PR without checking it out

`nitpick-pr` takes a pull request - its URL, `owner/repo#number`, or a bare
number for the repo at hand - and opens the forge's own diff of it in the pane.
One `gh pr diff`, nothing cloned, nothing fetched, no worktree. It is what
`gh pr diff <url> | diffnav` is for, with Emacs' lack of a stdin answered by
naming the PR instead of piping it.

The patch becomes magit sections rather than text: `magit-diff-wash-diffs` only
ever reads the buffer in front of it, so inserting the patch and washing it in
place produces exactly the sections `git diff` would have, and the pane narrows
to them as usual. Two details make that work:

- magit passes `--no-prefix` to every diff it runs, while a forge serves `a/`
  and `b/`. Left in, every file reads as a rename of itself, so the prefixes are
  stripped from the headers first - headers only, since a patch of a patch has
  lines inside its hunks that look like headers.
- A patch buffer refreshes by re-washing the patch, not by running `git diff`,
  which it has no repository for. That is a major mode of its own
  (`nitpick-pr-patch-mode`), because `magit-refresh-buffer` derives the refresh
  function from the mode's name.

The pane's file list is read back out of those sections - status from the kept
header, the rename source from the section, the counts by walking the hunks -
rather than from a second parse of the patch, so the pane and the diff cannot
disagree. The counts match `git apply --numstat` file for file.

What a patch has no answer for is the files. `o` in the pane and `RET` on a
hunk are the questions that need them, so they are what checks the PR out:
`git pr`, which finds the clone the URL names, fetches `refs/pull/N/head` and
leaves it in a sibling worktree - run with its stdout captured, which is what
keeps it a path emitter instead of also building a multiplexer session and an
editor workspace. It fetches, so it runs asynchronously.

The pane is then re-read from git in that worktree and lands on the file that
asked for it. Not handed the patch: `gh pr diff` is a three-dot diff and the
pane resolves its own base, so re-reading is what keeps the line numbers and
the sections consistent. From there the review is the full one - real files on
both sides, diff-hl painting them, `nitpick-comment` able to anchor a thread.
Until then `nitpick-comment` says so rather than failing at the forge.

So reading a PR costs one HTTP request, and only a review that opens a file
pays for a worktree. `pr-diff` and `pr-review`, the gh-dash keys, check out
first because diffnav and octo both resolve files against the checkout they
were started from.

## Whole-line highlighting

Two decisions, one each:

- **What is compared.** `nitpick-diff-hl-set-base` asks for a revision and
  diffs the project against it: a local branch, a remote-tracking ref like
  `origin/master`, a tag, a sha. It is used as picked, so `master` and
  `origin/master` are different answers. Pick `HEAD` for the usual view of
  your own uncommitted edits. Checking out a PR worktree sets it to the PR's
  base as the remote has it, and each worktree's last answer is what the
  prompt suggests next time.

  Nothing answered yet, the base is **inferred from the commit graph**: of
  every local branch, the one whose merge base sits closest to HEAD, with
  `...` appended. That is the branch HEAD left last, so a stack resolves to
  its parent - the parent's own tip *is* that merge base - and everything else
  to the default branch. Two rules keep it honest: a branch already merged into
  the default branch is not a candidate (a fast-forward merge leaves its tip
  exactly on your fork point, where it would otherwise outrank the default
  branch on nothing but its name), and the default branch wins a tie. On the
  default branch itself, or a detached HEAD, nothing is inferred.

  The order is: this worktree's last answer, the open PR's base, the graph,
  then the default branch as the remote has it. The forge comes first because
  it knows the answer where the graph only has evidence for it; the graph comes
  before the remote's default branch because it is right about a stack, and
  because a remote-tracking ref is only as current as the last fetch.

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
