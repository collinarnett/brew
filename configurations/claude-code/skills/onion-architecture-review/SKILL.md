# Onion Architecture Review

Review a codebase for dependencies that point the wrong way, and for code
that sits in the wrong ring. The governing question for every module: which
ring does it belong to, and does every edge leaving it point inward? Every
finding is a way that question fails. The prescriptions come from Palermo's
original statement of the pattern, Cockburn's ports and adapters, and the
functional-core framing of the same idea:

- https://jeffreypalermo.com/2008/07/the-onion-architecture-part-1/
- https://alistair.cockburn.us/hexagonal-architecture/
- https://www.destroyallsoftware.com/screencasts/catalog/functional-core-imperative-shell
- https://www.parsonsmatt.org/2018/03/22/three_layer_haskell_cake.html

Palermo's rule is exact and worth quoting to yourself before every finding:
*all code can depend on layers more central, but code cannot depend on layers
further out from the core. In other words, all coupling is toward the
center.*

Operate on whatever the user names — a module, a package, a whole repo.
Before judging anything, build the actual import graph: every module, every
module it imports, direction included. Then assign each module a ring and
write the assignment down. Every finding depends on that assignment, so a
report that does not state it cannot be checked, and a wrong assignment
produces a page of confident nonsense.

## The cardinal rule: direction is necessary, not sufficient

An edge can point inward and still invert the architecture. What matters is
not only which way the arrow runs but what travels along it. A core type
holding an HTTP status code, a SQL error string, an exit code, a terminal
width, or a byte offset into a wire frame is coupled to the outside no matter
how clean its import list looks — the outer layer can no longer change
without the core changing with it, which is the whole thing the rule exists
to prevent.

So judge coupling by vocabulary as well as by direction. A core that imports
nothing and speaks entirely in the outside's words has met the letter of the
rule and failed its intent.

## Categories

### 1. Outward edges

The literal violation: an inner module importing an outer one. List every
edge whose target sits in a wider ring, and give each its own finding.

The forms that hide: an inner module importing an outer one for a single
type in an error sum; an inner module re-exporting an outer one's types as
part of its own interface; a "shared" or "common" module that has quietly
accumulated an outer dependency and is imported by everything.

The fix is almost never to move the importer outward — that spreads the
outer ring inward one module at a time. Move the *type* inward if it is
genuinely a core concept, or translate at the edge if it is not.

This skill judges edges between rings, where one module is inside the other.
An edge between peers — two modules in the same ring that answer to different
authorities — is a context leak, and that finding belongs to
domain-model-review. Decide which of the two an edge is before reporting it,
and report it once.

### 2. Outer vocabulary in inner types

The cardinal rule as a category. Look for core declarations naming:

- transport and protocol detail — status codes, headers, wire offsets, framing
- storage detail — SQL fragments, driver error strings, column names
- presentation detail — exit codes, colour, terminal width, format strings
- process detail — environment variable names, argv shapes, signal numbers

```haskell
-- core, and yet: the caller must know what 404 means to use it
data LookupResult = LookupResult { status :: Int, body :: ByteString }
```

The fix is a type that answers the domain's question — `Found a | Absent` —
with the adapter translating in both directions at the boundary. The test:
if the program grew a second adapter for the same port, would this type still
make sense? A type that only makes sense over HTTP belongs to the HTTP
adapter.

### 3. Ports declared on the wrong side, or not at all

Inversion means the inner ring declares the capability it needs and the outer
ring supplies it. A core function taking a concrete outer type — a connection,
a file handle, a client object, a framework request — has skipped the
inversion even if the import direction happens to work out.

In a functional language the port is a function or a record of functions
passed in. No container, no interface file, no class hierarchy:

```haskell
-- the capability, declared by the core in the core's own words
newtype Clock = Clock { now :: IO UTCTime }
```

Flag also the port that is a grab-bag: a capability record with eight fields
where the core calls two. A port is a purposeful conversation, and the fields
nobody speaks are a dependency nobody declared.

### 4. Orchestration in the wrong ring

Two directions, both findings.

Decisions in the presentation layer: a CLI choosing a retry policy, a
handler deciding what counts as a duplicate, a view computing a total. If a
second front end would have to reimplement it to behave the same, it belongs
in the service ring.

Presentation in the service layer: a service formatting output, choosing
colour, printing, or deciding an exit code. Palermo's original complaint was
UI coupled to data access through the layers between; the modern version is
a service that has opinions about rendering. A service returns what happened;
the caller decides how it looks.

### 5. A core that cannot stand alone

The property that makes the pattern worth its cost: delete the outer ring and
the core still compiles and still means something. Testability is how the
literature phrases it, but compilation is the sharper criterion and needs no
test suite.

The usual reasons it fails, all of them ambient inputs reached for in place:

- the current time, taken by the code that needs it rather than passed in
- randomness and freshly generated identifiers
- environment variables and configuration read at the point of use
- the filesystem, the network, the clock's timezone

The fix is to take the value as an argument and let the shell obtain it.
A pure function handed a timestamp and a set of generated identifiers is core;
the same function calling out for them is not.

### 6. Ceremony without inversion

The pattern's own failure mode, and the one most likely to be present in
code that has read about the pattern:

- a ring that only forwards — every function a one-line delegation to the
  next ring in, adding a name and nothing else
- an abstraction with exactly one implementation, no second in prospect, and
  no boundary of change on either side of it
- mapping layers converting a type to a structurally identical type because
  the diagram says the rings must not share
- modules named for the pattern (`Service`, `Manager`, `Impl`, `Helper`)
  rather than for what they do

A ring earns its place by isolating a change: something on one side must be
able to move while the other side stays still. Where nothing changes
independently, the ring is decoration, and the finding is to delete it.

### 7. Logic stranded in the effectful ring

Direction can be perfect while the mass sits in the wrong place. Parsons'
three-layer framing supplies the missing rule: the innermost ring should hold
as much of the program as it possibly can, because that is the only ring whose
behaviour can be established exhaustively. A core of six type declarations
under a thousand lines of effectful orchestration is an onion in name.

What to look for, function by function in the outer rings:

- a function in `IO` (or the application monad, or a handler) whose body is
  mostly decisions — branching, arithmetic, sorting, assembling a result —
  with I/O at the top and bottom only
- a loop that reads, computes, and writes per iteration, where the computation
  does not depend on what the writes return
- error classification, retry policy, or fallback selection expressed inline
  among the calls that can fail
- validation performed against values fetched moments earlier in the same
  effectful function

The fix is the split, and it is mechanical: name the decision, lift it to a
pure function over the data it actually reads, and leave a caller that
fetches, calls, and writes. The caller becomes uninteresting, which is the
goal — the outermost ring should be too boring to hide a bug.

Judge each ring by what testing it would take. If establishing a rule requires
standing up a socket, a disc, a database, or a clock, the rule is in the wrong
ring. Report the ratio when it is lopsided: a package whose pure modules are a
tenth of its effectful ones is a finding on its own, independent of any single
function.

## Calibration

The number of ports is small. Cockburn's own intuition is two, three, or
four, and he notes there is little damage in getting the count wrong. A
program with one adapter, one core, and no abstraction between them may be
correctly built. Do not demand a port per external call, an interface per
class, or a folder per noun.

Language shapes the mechanism, not the rule. In a functional codebase,
passing a function is the whole of dependency inversion, and a record of two
functions is a complete port; demanding containers, registries, or class
hierarchies there is cargo cult. In a language with no first-class functions,
an interface is the same thing spelled differently.

Distinguish shared primitives from leaks. Types every ring genuinely shares —
a duration, an identifier, a checksum — are a kernel, not a violation. The
leak is a type *owned* by an outer ring appearing inward, and the tell is
which side's change forces the other to move.

Small programs are allowed to be flat. The pattern pays when infrastructure
is expected to change under a stable core; where the whole program is the
adapter, layering it is cost without return. Say so plainly rather than
finding violations in a script.

Prefer the smallest correction that removes the edge. Moving one type inward
or adding one translating function at the boundary usually fixes what looks
like a structural problem; propose a restructure only when the edge count
says the rings themselves are drawn wrong.

## Report

State the ring assignment first — every module, and which ring you placed it
in — because every finding below it is only as good as that assignment.

For each finding give file:line, the category, the offending edge written as
`inner-module → outer-module` with both rings named, and the concrete move:
which declaration goes where, or which translation function appears at which
boundary. Where a type must stay put, say what the adapter converts it to.

Order by direction of harm: outward edges first, then outer vocabulary held
inward, then misplaced orchestration, then logic stranded outside the core,
then ceremony. A codebase whose every
edge already points inward is reported as sound — do not invent violations to
fill a report, and do not report a flat program as an unfinished onion.
