# Domain Model Review

Review a codebase for names and modules that do not respect the boundaries of
the domain they model. The governing question for every module: does each
word in it mean exactly one thing, and does the module answer to exactly one
authority? Every finding is a way that question fails. The prescriptions come
from strategic domain-driven design — the half of Evans that survives
translation to a language with no ORM and no mutable object graph:

- https://martinfowler.com/bliki/BoundedContext.html
- https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf
- https://pragprog.com/titles/swdddf/domain-modeling-made-functional/

Operate on whatever the user names — a module, a package, a whole repo. Read
every export list before you read any body, and build a glossary as you go:
each domain word, where it is defined, and which outside authority decides
what it means — a file-format specification, a wire protocol, a vendor's
firmware, a business process. The findings live in the glossary, not in the
code. A word defined twice, a module exporting two glossaries, a word
invented where the authority already had one: none of these are visible from
a single declaration, which is why every other review misses them.

## The cardinal rule: contexts are found in the language, not the file tree

Never accept "these are both about X" as a reason two things share a module.
Proximity in a directory is not a boundary, and neither is a shared noun. The
test is whether one word means one thing throughout: if telling two
definitions apart in conversation needs a qualifier — "the *package*
manifest, not the *library* manifest" — they belong to two contexts, however
neatly they sit together on disk.

The converse holds just as hard. Never split a module because it is long, and
never merge two because they are short. Length is not a boundary. The only
boundary is a change of language or a change of authority.

## Categories

### 1. Polysemes

One word carrying two meanings inside a single boundary. Fowler's case is
"meter" in an electricity utility — the grid connection, the customer
relationship, and the physical device, all one word across three departments.
Conversation disambiguates by tone; a type system cannot.

The collision rarely appears as two identical identifiers, which the compiler
would refuse. It appears as one word spread across several:

```haskell
-- exported from Billing.hs — what a customer owes
newtype Account = Account { balance :: Cents }

-- exported from Billing.hs — the credential someone signs in with
data AccountCredentials = AccountCredentials { user :: Text, key :: Key }
```

Two concepts, one word, one export list: the ledger relationship and the
login. Search by word, not by identifier — grep for the noun and read every
declaration it touches. The fix is to rename in whichever context's speakers
already use a different word: if the auth system says *principal*, the
credential becomes `Principal` and `Account` is left to mean what the ledger
means by it. Module qualification alone is not a fix — it relies on every
future reader noticing which module a name came from.

### 2. Modules spanning two contexts

Symptoms, in order of reliability: the export list divides into clusters
whose members never appear together in one signature; two different outside
authorities can each force the module to change; the module's own doc comment
needs an "and also" to describe it.

A module holding both a file-format parser and a vendor's persistence record
has two masters — the format's specification and the vendor — and each will
drag it in its own direction forever. The fix is to split at the seam and
name each half for the context it serves, not for the data structure it
holds.

### 3. Translation mistaken for the model

Types that exist only to survive a hostile external format — URI resolution,
percent-decoding, path normalisation, wire framing, encoding quirks — given
the same prominence as the model, or forming the bulk of it. That work is an
anticorruption layer. It is necessary, it is often the most defect-prone code
in the program, and it is not the domain.

The measurement worth taking: what fraction of the type declarations translate
rather than model. When translation dominates, the domain is buried, and
every subsequent reader mistakes the parsing vocabulary for the subject
matter. The fix is to name the boundary as a boundary, keep it out of the
core's namespace, and let the core speak in types that have already been
translated.

### 4. Types leaking across a boundary

One context's type appearing in another's interface, error sum, or
re-exports:

```haskell
-- a transport-layer failure sum carrying a document parser's failure type
data TransportError
  = Timeout Expectation
  | BadPayload DocumentParseError
```

The transport layer now recompiles whenever the parser's failure modes
change, and its callers must understand a vocabulary from a context they
never entered. The fix is translation at the seam: the receiving context
names the failure in its own words and keeps the detail as a string or its
own sum. A shared kernel is the legitimate version of this — see Calibration.

This is a finding about peers: two contexts side by side, each with its own
authority. Where one module is genuinely inside the other and the dependency
runs outward, the violation is a layering one and belongs to
onion-architecture-review. Decide which before reporting, and report it once.

### 5. An unidentifiable core domain

Ask which module holds the knowledge nobody else in the world has. If the
answer is "it is in the comments", that is the finding. Hard-won facts about
what an external system tolerates — an empty list that crashes its renderer,
a queue that keeps only the last write before a restart, a display that is
one bit deep — are the reason the program exists and the reason it is hard to
replace. They
belong in types and module names, not in prose beside a function that happens
to respect them.

The same finding from the other side: generic subdomains sitting at equal
prominence with the core. XML helpers, zip mechanics, and image encoding are
solved problems that happen to be present; they should be quiet, and the core
should be loud.

### 6. Invented vocabulary over an existing one

The domain already had a word and the code coined its own. A wire protocol
says *subscriber*, a billing specification says *payer*, and the code invents
`User` for both. That third language is spoken nowhere outside the
repository, so every reading of a specification or a packet capture now costs
a translation step, and the two distinct concepts the sources kept apart
arrive merged.

Invent only where the authority genuinely has no word — and then use the
invented word everywhere, including in comments and error messages. Flag any
concept that goes by one name in a type, another in a function, and a third
in the message a user reads.

## Calibration

Most tactical DDD does not apply outside its home. Aggregates, repositories,
factories, domain events, and entity-lifecycle modelling assume a mutable
store and transactional invariants across an object graph. Do not propose any
of them for a pure transform, a CLI, or a pipeline; in a functional codebase
the tactical layer is value objects and parse-at-the-boundary, and that is the
whole of it. Evans came to regard the tactical patterns as the least
important part of his own book — take him at his word.

One context is the correct number for a small program. Boundaries cost
translation code, and paying for one before two vocabularies actually collide
is waste. The trigger is a real second authority, not a growth forecast.

A shared kernel is legitimate. Types every context genuinely shares — a
timeout, a checksum, a port path — are not leaks. The leak is a type *owned*
by one context turning up in another's interface, and the tell is which
context's change forces the other to recompile.

**Duplication across contexts is correct.** Two contexts modelling "book"
differently, with no shared type, is the intended outcome and not a DRY
failure. Deduplicate within a context; translate between them. A review that
collapses two contexts' models into one shared type has caused the exact
problem this skill exists to find.

Renaming across a published API is a breaking change: report it and say so.
And do not flag a codebase for lacking ceremony — a program with one clear
language, one authority, and no polysemes is reported as having a sound
model, however few types it has.

## Report

For each finding give file:line, the category, the two readings the name or
module currently carries, and the concrete split, rename, or translation. Say
which authority owns each side of every boundary you propose — a boundary
whose two sides cannot be named is not a boundary.

Order by blast radius: polysemes and context-spanning modules first, since
they mislead every reader of every line; then leaked types; then vocabulary
drift. A codebase whose language is already consistent is reported as clean —
do not invent findings to fill a report.
