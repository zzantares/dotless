---
name: chop
description: Rewrite the response you just gave so it fits a word budget (120 by default), verified with wc -w instead of estimated. Use when the user says "chop", "/chop", "too long", "shorter", "cut it down", "tl;dr that", or gives a number of words to hit. Also use when asked to shorten a file, a PR body, a commit message, or pasted text to a specific length.
---

Cut a piece of text to a word budget without losing what the reader acts on.

## Target and budget

- **Target**: the immediately preceding response, unless the user names something else (a file, a PR body, pasted text).
- **Budget**: the number the user gave, else **120 words**.

## Count with wc, never by eye

Word counts guessed from a draft are wrong often enough to matter. Write the
draft to a temp file and count it:

````bash
# fenced code is exempt from the budget, so strip it before counting
awk '/^```/{f=!f; next} !f' DRAFT | wc -w
````

Over budget: cut and recount. Stop after three passes - hand back the shortest
draft and state its count rather than looping.

## What to cut

In order, until it fits:

1. Preamble, and any sentence that previews what the answer will say.
2. Restatements of the question.
3. Options you are not recommending. Give the recommendation alone.
4. Hedges, and caveats the user already knows.
5. Adjectives that carry no fact.
6. Prose connectives between list items.

## What to keep

- Numbers, file paths, commands, flags, error text - verbatim.
- Code blocks and diffs, uncut and uncounted.
- Any caveat that changes what the user does next.
- The answer itself. A shorter response that no longer answers the question is
  a failed chop, not a successful one.

## Rules

- Sacrifice grammar before facts. Fragments and lists are fine.
- Do not game the count: no reformatting prose into a table, no moving text
  into a code fence to make it exempt.
- Print the final text only. No drafts, no pass-by-pass narration, no report
  of what you cut unless the user asks.
- If the budget cannot hold the answer, say so in one line and give the
  shortest honest version.
