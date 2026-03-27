# Prose Review

Review the specified file (or the most recently edited prose file) for AI-sounding patterns and fix them. This skill enforces a direct, technical, human writing voice.

## What to look for

### Banned words and phrases

Remove or replace these on sight:
- "delve", "dive into", "it's important to note", "certainly", "it's worth noting", "arguably"
- "crucial", "pivotal", "bolstered", "underscore", "emphasizing"
- "Additionally", "Furthermore", "Moreover" as sentence openers
- "In today's fast-paced world", "As technology continues to evolve"
- "without further ado", "it goes without saying", "have you ever wondered"
- "Let's unpack", "multifaceted", "ascertain"
- "navigating the landscape", "at the end of the day"

### Structural patterns to fix

- **Em dashes for dramatic effect.** Replace with commas, periods, or parentheses. Em dashes are fine for genuine parentheticals but not for rhythm or flair.
- **"It's not X — it's Y" parallelism.** Rewrite. Once per piece is fine. More than that is a tell.
- **Uniform sentence length.** Vary rhythm. Mix short punchy sentences with longer compound ones.
- **Short listy sentences.** Combine into flowing paragraphs. Bullets are for reference material, not narrative.
- **Aphoristic chains.** "We can't X what we can't Y. And Y requires Z. That's what this gives us." Rewrite as a single concrete statement.
- **Colon-heavy headers.** "The Problem: Why X Matters" — just say what it is.
- **Arbitrary bolding.** Bold should highlight terms of art or navigation landmarks, not add emphasis to random phrases.
- **Excessive hedging.** "typically", "might be", "may", "it could be argued" — commit to the claim or cut it.

### Content patterns to fix

- **Generic claims without specifics.** "This improves performance" — how much? Compared to what?
- **Empty summary sentences.** "This approach provides a solid foundation for future work." Delete these.
- **Forced metaphors.** If the metaphor doesn't earn its keep with genuine explanatory power, cut it.
- **Filler.** If three sentences can be one, make it one.
- **Unearned profundity.** "Something shifted.", "Everything changed." — say what actually happened.
- **Wrong grammatical subject.** The interesting thing should be the subject of the sentence, not buried in a subordinate clause.

## Process

1. Read the entire file first to understand voice and context.
2. Match the existing voice of the document. Do not impose a generic blog tone.
3. Make a first pass identifying every violation. List them with line numbers.
4. Fix each violation. For each fix, show the before and after so the user can review.
5. After all fixes, re-read the full document to check that it flows naturally and hasn't become choppy from individual edits.
6. Be technically specific. If you're replacing vague language, replace it with concrete details from the surrounding context — don't just delete it.
