---
name: deslop
description: Audit or rewrite text to remove the stylistic fingerprints of LLM writing - AI vocabulary, negative parallelisms, rule-of-three padding, promotional filler, weasel attributions, em dashes, curly quotes, emoji headers, and leaked citation markers. Use when the user says "deslop", "de-slop", "sounds like AI", "make this sound human", "remove the AI tells", or asks to review prose (docs, READMEs, PR bodies, commit messages, blog posts, release notes) for AI-generated style. Also use before publishing text an LLM drafted.
---

Strip the tells of machine-written prose without flattening the author's voice.

Adapted from [Wikipedia:Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing), the community's field guide for spotting LLM text.

## Two modes

- **Audit** (default when the user asks "does this sound like AI?"): report the tells you find, quote each one, do not edit.
- **Rewrite** (default when the user says "deslop this"): produce the corrected text. List what you changed only if asked.

If the target is ambiguous, rewrite.

## First rule: a tell is evidence, not a verdict

One or two hits mean nothing. Density is the signal. Real authors write "crucial" and use the rule of three. Fix what is genuinely padding; leave what carries meaning.

Never accuse a human author of using AI. Report the writing, not the writer.

## Content tells

- **Significance inflation.** Sentences that exist to say the subject matters: "stands as a testament to", "cemented its legacy", "reflects broader trends in". Cut them. A fact establishes significance; a sentence claiming significance does not.
- **Canned notability padding.** "has been featured in numerous publications", "garnered widespread acclaim", "received coverage from outlets including". Replace with the specific coverage or delete.
- **Superficial analysis.** A paragraph that restates the topic in more words and concludes nothing. Delete or replace with a claim.
- **Promotional register.** Adjective stacking, "seamlessly", "cutting-edge", "rich history", "vibrant community". Neutral verbs and concrete nouns instead.
- **Weasel attribution.** "experts argue", "observers have noted", "industry reports suggest", "several sources", "described in scholarship". Name who said it, or drop the claim. Also watch overgeneralization: two citations presented as a consensus.
- **"such as" before an exhaustive list.** Implies more examples exist when the list is everything you have. Use "namely" or just list them.
- **Outline-shaped endings.** A trailing "Challenges and future prospects" / "Looking ahead" paragraph that hedges in both directions. Cut it or make it a concrete claim with a consequence.
- **Bolt-on "Awards and recognition".** Fold into the narrative unless the awards carry real weight.

## Vocabulary

Words LLMs overuse. One is fine; a cluster is the strongest single tell. Their synonyms are *not* implicated - do not thesaurus your way around the list, rewrite the sentence.

Watch: *additionally* (sentence-initial), *align with*, *boasts* (meaning "has"), *bolstered*, *crucial*, *deep dive*, *delve*, *emphasizing*, *enduring*, *enhance*, *fostering*, *garner*, *highlight* (verb), *interplay*, *intricate/intricacies*, *key* (adjective), *landscape* (abstract), *meticulous(ly)*, *pivotal*, *robust*, *seamless*, *showcase*, *tapestry* (abstract), *testament*, *underscore* (verb), *valuable*, *vibrant*.

Era buckets, useful for dating a draft:

- 2023 to mid-2024 (GPT-4): *delve, tapestry, testament, pivotal, meticulous, intricate, interplay, boasts, vibrant, landscape, underscore, additionally*
- Mid-2024 to mid-2025 (GPT-4o): *align with, bolstered, enhance, fostering, highlighting, showcasing, underscore, vibrant*
- Mid-2025 on (GPT-5): *emphasizing, enhance, highlighting, showcasing*, plus canned notability padding
- Grok: pseudo-scientific *causal, empirical, correlate*, still *underscore*

Context matters. "Underscore" as a literal underline mark or incidental music is fine.

## Sentence shapes

- **Negative parallelism.** "Not just X, but Y", "not X, but rather Y", "X rather than Y" used for emphasis rather than contrast. The most portable tell across models. Delete the negated half and state Y.
- **Rule of three.** Three adjectives, three clauses, three examples, over and over. Keep the ones that carry information; two is usually right, one is often enough.
- **Copulative avoidance.** Dressing up "is" as "serves as", "stands as", "functions as", "represents". Use "is".
- **Vague connection.** "is closely tied to", "plays a role in", "is associated with", "reflects" - hedges that assert a link without naming it. State the mechanism or cut the sentence.
- **Participial tails.** Clauses ending in "-ing" that add a moral: "..., highlighting the importance of collaboration." Cut the tail.

## Style and formatting

- **Em dashes and en dashes.** Replace with a plain hyphen, comma, or full stop.
- **Curly quotes and apostrophes.** Straighten to `'` and `"` in code, config, and plain text.
- **Title Case Headings.** Use sentence case unless the surrounding document does otherwise.
- **Title heading repeating the document name.** Delete.
- **Boldface overuse.** Bold **inside** running prose for keyword emphasis. Keep at most what a reader would scan for.
- **Inline-header bullet lists.** `- **Thing**: description` repeated for every item where prose would do. Fine for genuine key-value lists, slop when it is a chopped-up paragraph.
- **Emoji as section markers**, decorative tables holding two facts, thematic breaks (`---`) between every section, skipped heading levels, multiple level-1 headings. Remove.
- **Headings containing only headings**, with no body text between them. Merge.

## Leaked markup

Delete on sight - these are pure model exhaust:

- ChatGPT: `contentReference`, `oaicite`, `oai_citation`, `turn0search0`, `attributableIndex`, stray `+1`
- Gemini: `[cite: 1]`, `[span_1](start_span)`
- Grok: `grok_card`, `grok_render_citation_card_json`
- DeepSeek: lenticular brackets `【 】`, dagger symbols
- Perplexity: `attached_file`, `ppl-ai-file-upload`
- Markdown syntax inside a non-Markdown format; broken or half-closed markup

Also delete:

- **Chatbot talking to the user.** "Let me know if you'd like me to expand this", "Here's a draft you can adapt", "I hope this helps".
- **Knowledge-cutoff hedges.** "As of my last update", "sources may have changed since".
- **Placeholder text.** `[Insert date]`, `[Your Name]`, `[Add citation here]`, unfilled templates.

## Verification

Facts LLMs invent, worth checking when the text cites anything:

- Dead or wrong external links; URLs whose slug does not match the claimed title
- Invalid DOIs and ISBNs (wrong checksum, wrong length)
- Citations to real authors for papers they did not write
- Non-existent templates, categories, or cross-references

Flag these in audit mode. Do not silently delete a citation in rewrite mode - mark it for the author.

## Rewrite procedure

1. Read the whole text first. Judge overall density before touching anything.
2. Cut whole sentences and paragraphs that carry no claim. This is the highest-value edit and comes before word substitution.
3. Fix the sentence shapes: negative parallelisms, copulative dodges, participial tails, triples.
4. Replace vocabulary hits by rewriting the sentence, not by swapping synonyms.
5. Fix formatting and delete leaked markup.
6. Reread for meaning drift. You must not have changed any factual claim, added a claim, or dropped a caveat that changes what the reader does.

Preserve: the author's technical vocabulary, structure that a reader relies on, code, quotes, and anything inside a quotation.

## Audit output

Group by tell, most severe first. For each: the category, the quoted text, and the fix in a few words. Close with a one-line verdict on density - whether the tells cluster enough to be a real signal or read as normal writing. No preamble.

## Anti-goals

- Do not shorten for its own sake. Deslopping removes filler, not substance.
- Do not homogenize voice. Idiosyncratic, informal, or opinionated writing is the opposite of slop; leave it alone.
- Do not flag every instance of a listed word. Report the pattern, not a word count.
- Do not add hedges, disclaimers, or a summary the author did not write.
