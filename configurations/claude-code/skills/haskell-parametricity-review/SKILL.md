# Haskell Parametricity Review

Review Haskell code for functions whose signatures claim more capability than
their logic uses. A monomorphic signature permits every implementation the
concrete type allows; a polymorphic one proves the function cannot inspect,
conjure, or special-case its values. The prescriptions come from Justin Le's
writing on parametricity and interface choice:

- https://blog.jle.im/entry/five-point-haskell-part-2-unconditional-election.html
- https://blog.jle.im/entry/functors-to-monads-a-story-of-shapes.html

Operate on whatever the user names. For each function, read the body and ask:
does the logic ever inspect the concrete type, or does it only move values
around, compare them, count them, or thread them through other functions?

## Generalize when the body never looks inside

Treat monomorphic code with suspicion. When a function's logic is independent
of the concrete type, the generalized signature is a free theorem the reader
gets without reading the body:

- a function on `Set Text` that only uses `size`, `member`, and
  `intersection` is `Ord a => Set a -> …`; the signature proves the logic is
  blind to the values' content
- a selection function typed `NonEmpty Double -> Double` that only sorts and
  indexes is `Ord a => NonEmpty a -> a`; the signature proves it returns an
  *element* of the input, never an average or other fabricated value
- a function iterating a `[User]` only to feed each to an action is
  `Foldable t => t a -> (a -> IO ()) -> IO ()`; the signature proves every
  element is treated identically

The value is documentation and constraint, not reuse. Generalizing a helper
nobody will reuse is still correct when the polymorphic signature states an
invariant the monomorphic one hides. Name that invariant in the finding — a
generalization you cannot attach a guarantee to is not a finding.

## Constraint minimality

The same suspicion applies to constraints and interfaces:

- `Ord` where `Eq` suffices, `Show` used for logic rather than display,
  `Monad` where `Applicative` suffices
- effectful traversals whose shape is fixed up front: independent actions
  written with monadic sequencing when `traverse` states the independence in
  the type — and, where latency matters, unlocks concurrent execution via an
  `Applicative` like `Concurrently`
- `IO` taken directly where the function only needs to sequence effects it
  was handed, so `Applicative f`/`Monad m` would prove it performs none of
  its own

A data dependency — the next action's shape depending on the previous
result — genuinely requires `Monad`; that is not a finding.

## What stays monomorphic

Generalization is for logic, not domain. Do not flag:

- functions that pattern match on domain constructors, read fields, or
  build domain values — their monomorphism is their meaning
- application pipelines gluing subprocesses, parsers, and IO together;
  polymorphism there documents nothing and costs readability
- code whose only caller passes one type and whose signature already states
  every invariant worth stating

An application is mostly domain; expect few findings and let that be the
report. Wholesale `mtl`-style effect abstraction is likewise not a goal —
plain `IO` application code is fine, and typeclass-polymorphic effects earn
their place only when a second interpretation actually exists.

## Report

For each finding give file:line, the current signature, the generalized
signature, and the specific guarantee the generalization proves — the free
theorem in one plain sentence. If nothing warrants generalizing, say the
code is appropriately monomorphic rather than manufacturing findings.
