# Property Design

Design a test suite that is capable of failing. Use this when adding tests,
when a bug got through a green suite, or when a reimplementation has to be
shown equivalent to the thing it replaces. The taxonomy comes from John
Hughes' guide to specifying pure functions:

- https://research.chalmers.se/publication/517894/file/517894_Fulltext.pdf

The principle is language-agnostic; the examples are Haskell, where the
generator and the shrinker come from the library and the property is the only
part left to think about.

## The cardinal rule: name the bug first

Before writing a test, state the mistake it catches. Then make that mistake —
break the implementation, run the test, watch it go red, restore the code.
A test whose failure mode cannot be stated is decoration, and a test that has
never been observed failing is an assertion about nothing.

This is the whole reason to distrust a suite written alongside the code it
tests: both were produced from the same understanding, so the test encodes the
implementation's shape rather than the specification's. Properties resist this
because they are written about the problem, not about the code.

## The five sources of properties

Work through all five for the unit under test. Record which apply and which do
not, and why — "no algebraic laws here" is a finding worth writing down, since
a type with no laws is often a type that has not been thought about.

### 1. Invariants

What is true of every value the code produces, regardless of input. A balanced
tree stays balanced. A parsed document's internal references all resolve. A
rip manifest names a playlist that exists on the disc. Write the invariant as a
predicate over the type, export it from the test module, and assert it after
every operation that produces the type.

The strongest version of this finding is not a test at all: if the invariant
holds for every value the type can hold, the constructor should enforce it and
the property becomes unnecessary. Check for that before writing the test.

### 2. Postconditions

What the output satisfies given the input. Weaker than it looks in practice,
because the obvious postcondition often restates the implementation. Prefer
postconditions that mention only the inputs and the problem domain: after
`insert k v m`, looking up `k` yields `v` and every other key is unchanged.

### 3. Metamorphic properties

How the output changes when the input changes in a known way. This is the
highest-yield source and the one most often skipped, because it does not
require knowing the expected output for any single input — only the
relationship between two runs.

Look for: adding an element, reordering the input, scaling a parameter,
concatenating two inputs, applying the operation twice, running the same input
through two configurations that should agree. `parse (a <> b)` relates to
`parse a` and `parse b`. Selecting a playlist from a disc twice returns the
same playlist. Encoding at a higher quality never produces a smaller file.

### 4. Algebraic laws

Identity, inverse, idempotence, associativity, commutativity, distribution
over another operation. Round-trips are the common case and the most valuable:
`decode . encode == id`, `parse . render == Right`, `import . export == id`.

Round-trip properties fail in an informative direction. Generate the *rich*
side and go out and back, so the generator explores the structure rather than
the serialization. Generating text and asserting `render . parse == id` tests
mostly that the generator emits valid text.

### 5. Model-based

The operation agrees with a simpler reference. The model can be an obviously
correct but slow implementation, a data structure with different performance
characteristics, or another library that already solves the problem. The
property is that the real thing and the model agree on every generated input.

This is the source that covers a reimplementation, and it belongs in the suite
from the first commit of the port rather than after the bug reports.

## Stateful interfaces

Anything with a lifecycle — a device, a session, a cache, a sequence of
subcommands that share state on disk — is not covered by testing each
operation alone. The bugs live in the orderings.

Model the state as a plain value, define each command's precondition,
transition, and postcondition against that model, and let the library generate
command sequences. `quickcheck-state-machine` and Hedgehog's state machine
support both do this, and both shrink a failing sequence to the shortest one
that still fails, which is where their value is: the output is a two-command
reproduction rather than a forty-step log.

Parallel command sequences additionally find races for free. Use them wherever
concurrency is real.

## Differential testing against a reference

When correctness means "agrees with the thing we replaced", the specification
is the other implementation, so run both:

1. Generate inputs in the domain — not a corpus of collected files. A corpus
   samples what somebody happened to have; it says nothing about the rules.
2. Run both implementations over each input.
3. Compare outputs structurally, normalizing only differences that are
   genuinely permitted, and state each normalization explicitly. Every
   normalization is a claim that a difference does not matter, and a wrong one
   silently hides the bug you are hunting.
4. Keep the reference in the test dependencies, invoked as a subprocess if the
   languages differ.

Where the reference has its own test suite, run your implementation against
that suite directly. It is a specification somebody already wrote down.

## Generators

The generator decides what the property can find. A property that only ever
sees valid, small, well-formed inputs proves nothing about the failure paths.

- Generate the domain type, not its serialization, and derive the serialized
  form from it.
- Include the shapes the code special-cases: empty, single-element, maximum
  size, duplicate keys, non-ASCII text, absent optional fields.
- Generate invalid inputs deliberately for the parser, and assert that
  rejection is total and typed, not that it happens to throw.
- Check the distribution before trusting the result. A generator that produces
  a non-empty list 2% of the time gives a property that passes for the wrong
  reason; `checkCoverage` and label-based coverage exist for this.
- Let the library shrink. Hand-written shrinkers that lose the invariant
  produce failures that cannot be reproduced.

## Golden tests

Golden files pin output that is large, structured, and expected to be stable:
rendered reports, serialized manifests, CLI help text, error messages. They
catch unintended drift that no property would notice, and they document the
format for a reader.

Golden files are reviewed as source, so regenerate deliberately and read the
diff. A workflow where the accepted fix for a failing golden test is to
regenerate it has converted the suite into a record of what the code does.

## Closing the loop

The suite itself needs a test, and coverage percentage is not it — line
coverage says the code ran, never that a mistake would have been caught.

Mutation testing answers the real question: break the code deliberately,
assert the suite goes red. Surviving mutants are proven gaps. For Haskell,
`sydtest`'s `mutationCheck` does this from a flake check
(https://cs-syd.eu/posts/2026-06-03-mutation-testing-in-haskell). It
instruments the library through a GHC plugin, which is agnostic about the
test framework, but its coverage phase invokes the test binary with
`--mutation-coverage-list` — a sydtest flag. A suite built on another
framework compiles instrumented and then fails there, so a project that
wants mutation testing writes its tests with sydtest from the start.

Treat every surviving mutant as a finding: kill it with a test, or record why
the mutation is semantically meaningless. Do not silence it by loosening the
assertion that failed to catch it.

## Report

For each unit under test, list the five sources with the property written for
each or an explicit "not applicable, because …". Then state, for the suite as
a whole, which mutants survive and what was done about them. A suite whose
properties are all postconditions restating the implementation is reported as
weak even when every test passes.
