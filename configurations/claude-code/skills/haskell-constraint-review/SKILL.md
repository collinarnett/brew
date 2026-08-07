# Haskell Constraint Review

Review a Haskell diff for constraint-evading compromises: places where code
satisfied the compiler by weakening the rules instead of meeting them. The
categories come from Justin Le's catalog of LLM failure modes in Haskell
(https://blog.jle.im/entry/llms-and-haskell-1-constraint-evading-behavior.html).
Types and warnings are the reviewer that never tires; these patterns are how a
change slips past them, so each one found is a finding even when the code
"works".

Operate on the staged diff by default, or the commit range, branch, or PR the
user names. The diff decides where to start; the types decide what to check.
For every changed function, read the whole definition, then the definitions of
the types it consumes and produces — most of these compromises are invisible
in a hunk and obvious next to the type.

## Categories

### 1. Suppressed warnings

Any new escape hatch is a finding; deciding a warning does not matter is the
maintainer's call, never the implementer's. Grep the diff for:

- `OPTIONS_GHC` pragmas adding `-Wno-*` or `-fdefer-*`
- `ghc-options` edits in `*.cabal` or `package.yaml` that drop `-Wall`,
  `-Werror`, or any specific warning
- `{- HLINT ignore ... -}` / `-- hlint ignore` comments, `.hlint.yaml` edits
- newly introduced partial escape hatches: `error`, `undefined`, `fromJust`,
  `head`/`tail`, `unsafePerformIO`, `unsafeCoerce`, incomplete lambdas

### 2. String stuffing

Data encoded into strings because the honest type would demand more work:

- error text stuffed into a semantically wrong constructor:
  `UnknownUser ("Invalid group: " <> g)` where the user is known and the
  group is not
- sentinel values as signals: `ErrorCode (-1)`, `Canceled Nothing`, an empty
  `Value`, `""` standing in for absence
- structure serialized into a `Text`/`String` field that pattern matching or
  a parser downstream has to pick apart again

The fix is a constructor or newtype that says what happened. Fields typed
`String`, `Int`, `Value`, or `SomeException` are the abusable ones; flag new
uses that smuggle a different concept through them.

### 3. Field stuffing

Record fields carrying a second meaning because they happened to have the
right type:

- extra data appended into a list field (`authors ++ affiliations`)
- sentinel values dodging a schema change: `ModifiedJulianDay 0` instead of
  `Maybe Day`, `0` or `-1` instead of a new constructor
- a field reused for an unrelated purpose on some code paths

The honest fix is a new field or a new type. The downstream churn that causes
is the point: an API change is supposed to force thought at every use site,
and stuffing exists to avoid exactly that.

### 4. Weakened types

Signatures and definitions quietly broader than intended:

- `[a]` where the logic requires non-emptiness (look for paired `null`
  checks), `Int` where only naturals make sense, `Text` where a sum type
  enumerates the cases, `Value`/`Object` where a domain record was called for
- constraints swapped for weaker ones the implementer found convenient
- `Maybe` added to a field or result to dodge totality rather than to model
  genuine absence
- defensive `isNothing`/`isJust`/`null` guards where a pattern match should
  force the case analysis

Check every changed signature against whatever plans are recorded: design
docs, `HANDOFF`/`PLAN`/`TODO` files, issue or PR text, comments quoting
intended types, and the plan agreed in conversation when there is one. A
divergence may be an improvement, but it is never the implementer's
unilateral call — flag it and say what was planned versus what shipped.

### 5. Types that grew wrong

When a type changed, judge the shape of the change, not just its uses:

- flat expansion where a nested type was warranted:
  `data Region = State ... | Canada | Mexico` instead of
  `USState State | Country Country`
- a new constructor whose payload duplicates another's, differing only in
  which strings get stuffed into it
- a widened field type (`Int` → `String`, concrete → `Value`) that makes
  previously unrepresentable states representable again

## Code that did not change but should have

The diff view is blind here, so this pass is mandatory, not optional. For
every type whose definition changed, grep the whole project for its
constructors and field names and read each use site:

- a pre-existing `_ ->` or catch-all pattern now silently absorbs a new
  constructor; the compiler stayed quiet precisely because the escape was
  already there
- a function consuming the type still handles only the old shape and
  "works" by sentinel or by `Maybe`-collapse
- a serializer, `Show`/`ToJSON` instance, or pretty-printer that enumerates
  cases and was not extended

For every changed function, check its callers: a strengthened precondition or
a new failure mode that no caller was updated for is the same evasion viewed
from the other side.

## Report

For each finding give file:line, the category, the constraint that was
evaded, and the honest alternative (the constructor, field, or type that
should exist instead). Order by severity: silent data corruption first, then
suppressed diagnostics, then style-level weakening. If the diff is clean,
say so plainly rather than inventing findings.
