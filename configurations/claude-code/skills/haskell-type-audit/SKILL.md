# Haskell Type Audit

Audit a Haskell module or codebase for places where an invariant is enforced
by runtime discipline when the type system could enforce it instead. The
prescriptions come from Justin Le's writing on defensive typing:

- https://blog.jle.im/entry/five-point-haskell-part-1-total-depravity.html
- https://blog.jle.im/entry/sum-types-and-subtypes-and-unions.html
- https://blog.jle.im/entry/levels-of-type-safety-haskell-lists.html

Operate on whatever the user names — a module, a package, a whole repo. Read
every data declaration and every exported signature, then the bodies. The
governing question for each finding is what the *type admits*, never what the
code happens to do at runtime.

## The cardinal rule: no runtime simulation

Never excuse a pattern because a guard elsewhere keeps it safe. "The `!!` is
fine because the caller checked the length" is a description of today's call
graph, not a property of the code; the next refactor breaks it silently.
Severity comes from the states the type permits. A partial function protected
by a distant check is a finding. A sentinel that only reaches display code is
a finding. Rate them lower if you must, but report them.

## Categories

### 1. Sentinels standing in for absence or failure

- `""`, `[]`, `mempty`, `0`, `-1` meaning "missing", "unknown", or "failed"
- `Map.findWithDefault`, `fromMaybe` at a boundary that then loses the
  distinction between absent and empty forever
- one return value conflating several distinct worlds: a lookup that returns
  an empty map whether the source was missing, unreadable, or genuinely empty

The fix is `Maybe`, `Either`, or a sum naming each world. Watch especially
for a sentinel that a *second* module compensates for with its own guard —
two functions conspiring to keep a lie safe.

### 2. Booleans re-deriving a case split

- a flag computed from data (`hasItems = not (null items)`) and then
  branched on repeatedly, when the data itself should be a two-constructor
  sum carrying the payload only one case has
- paired values whose combinations are partly nonsense: a `(list, Bool)`
  result where one combination can never occur but must still be handled
- bare `Bool` parameters whose meaning is invisible at the call site
  (`render True False`)

The fix is a sum type whose constructors carry exactly the data their case
needs, making the meaningless combination unrepresentable.

### 3. Guarded partiality

- `head`, `!!`, `fromJust`, `minimumBy`/`maximumBy` on possibly-empty
  structures, incomplete patterns — anywhere totality depends on a check the
  type does not record
- documentation stating a precondition ("do not pass an empty list") instead
  of a type enforcing it

The fix is `NonEmpty`, a witness parameter, or restructuring so the check
*produces* the value that proves it happened. A `Bool`-returning predicate
followed by code that proceeds as if it returned proof is the same defect:
parse into a type, don't validate and forget.

### 4. Untagged same-type parameters

- adjacent parameters of the same type where swapping them type-checks
  (`FilePath -> FilePath -> IO ()` for a source and a destination)
- type aliases used where distinct concepts need distinct types

The fix is newtypes or a record with named fields. Weigh arity: at two
same-type arguments a newtype pair suffices; past a handful of parameters a
record earns its keep regardless.

### 5. Invariants without smart constructors

- a type whose comment states an invariant the constructor does not enforce
- validation performed at one boundary while another code path constructs
  the type directly

The fix is an abstract type: unexported constructor, a `mk*` function
returning `Maybe`/`Either`, and the proof travels with the value for its
whole lifetime.

### 6. Sums versus subtypes

Sum types fit a fixed set of cases with open-ended operations; typeclass or
record-of-functions polymorphism fits fixed operations over open-ended cases.
Flag a sum that grows a new constructor every time a backend or provider is
added, and flag typeclass machinery over a closed set of two cases that a
plain sum would state more simply.

## Calibration

The ergonomic ceiling for application code is newtypes, sums, `NonEmpty`,
and smart constructors. Do not propose length-indexed vectors, GADT-encoded
invariants, or singletons for ordinary code; that machinery is for library
interiors where the invariant is the product. Equally, do not flag domain
logic for using plain lists where emptiness is genuinely meaningful. The
audit finds types that *lie*, not types that could be fancier.

## Report

For each finding give file:line, the category, the state the current type
admits that the code pretends it cannot, and the concrete replacement type
or signature. Order by severity: silent data conflation first, then
partiality, then call-site ambiguity. A clean module is reported as clean —
do not invent findings to fill a report.
