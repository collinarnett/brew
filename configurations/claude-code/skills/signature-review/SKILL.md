# Signature Review

Review code for functions whose signatures cannot be understood alone. The
governing question for every function: could a reader holding only the
signature — the types and the parameter names, never the body — say what
each argument is and why the function needs it? Every finding is a way that
question fails. The principle is language-agnostic; the examples are
Haskell, where the signature is a separate line the reader meets first, but
the same failures appear in Python keyword arguments, Go struct parameters,
and TypeScript options objects.

Operate on whatever the user names — a module, a diff, a whole package. For
each function, read the signature first and write down what you believe each
argument means. Then read the body. Every place your belief was wrong or
empty is a finding.

## The cardinal rule: names are read where they are used

A parameter is named once but read at every call site and every use in the
body, usually far from the signature and always far from the type
definition. A name that only makes sense next to its type annotation is not
doing its job. Judge every name at its worst use site, not at its binding.

## Categories

### 1. Grab-bag arguments

A function takes an aggregate — a CLI flag record, an options object, a
context struct — and uses one field of it:

```haskell
readDisc :: IOE e1 -> Console e2 -> Common -> Config -> DiscRef -> Eff es Scanned
```

`Common` answers nothing. What does reading a disc need from the shared
command-line flags? The body knows (only `commonQuiet`, to decide progress
display), but the signature hides it, and every caller must thread the whole
bundle to satisfy one branch. The fix is to derive the precise value once at
the boundary and pass a type named for the question it answers:

```haskell
readDisc :: IOE e1 -> Console e2 -> Config -> ProgressStyle -> DiscRef -> Eff es Scanned
```

Now the signature states the dependency exactly. Flag any parameter whose
fields are mostly unread, and especially one that is only ever forwarded to
callees — a bundle nobody opens is a dependency nobody declared.

### 2. Evidence threaded instead of conclusions

The raw inputs to a decision travel through the program so each function can
re-derive the decision:

```haskell
-- quiet and a terminal check, recombined at every site
verbose = not bars && not (commonQuiet common)
```

Decide once at the boundary, name the outcome, and pass that:

```haskell
-- | How long operations show their progress, decided once at startup.
data ProgressStyle = Bars | MessageRows | Quiet
```

The same shape as `Session = Interactive | Headless` decided from stdin:
downstream code matches on a named conclusion instead of repeating the
inference. In any language, a pair of booleans combined the same way in
three places is one enum decided in one place.

### 3. Type names that do not name the concept

A type whose name admits several readings fails the signature test even with
a perfect parameter name. `Progress` — a percentage? a callback? a
report? It was a display style, so its name is `ProgressStyle`. The test:
say the name to someone who has not seen the definition and ask what they
expect. Words that routinely fail it: `Info`, `Data`, `Context`, `Manager`,
`State`, `Options`, `Common`, `Item`. The name should be the question the
value answers — `ProgressStyle` answers "how is progress shown?",
`Session` answers "is anyone at the terminal?".

### 4. Parameter names mute at the use site

The name gives no more information than the type already did, or less:

```haskell
resolveTitle io con ex config session report ident known
```

`report` is a parsed disc (`Disc`) — call it `disc`. `known` is a title
already settled by a flag or recognition — call it `knownTitle`; bare
`known` reads as a boolean. In the body, `case known of` says nothing;
`case knownTitle of` says everything. Likewise `style` → `progressStyle`,
`flagged` → `flaggedSource`. A name earns length in proportion to the
distance between its binding and its uses: a lambda's `x` used on the same
line is fine; a function parameter read two hundred lines later is not.

### 5. Call sites that read as noise

Adjacent same-type arguments and bare literals make the call site
unreviewable:

```haskell
render True False
copy src dst        -- which order does copy take?
```

In Haskell the deep fix is a type — a two-constructor sum for the bool, a
newtype pair for the paths — and that audit lives in haskell-type-audit. In
languages with keyword arguments or struct literals, the naming layer alone
fixes it: `render(bars=True, verbose=False)`, `Copy{From: src, To: dst}`.
Flag the call site either way; choose the fix the language affords.

## Argument order

Order parameters from most stable to most specific: capabilities or
dependencies, then configuration, then run context, then the subject of the
call. Consistent order across a module means a reader who has learned one
signature has learned them all, and partial application (where the language
has it) closes over the stable prefix naturally.

## Calibration

Established idioms stay: one-letter type variables, `i` in a tight loop, a
codebase's fixed capability names (`io`, `con`, `ex`) whose types sit one
token away in the same signature. Do not demand Hungarian notation or
restate the type in the name (`configConfig`); the name adds the *role*,
not the type. Renaming across a published API is a breaking change — report
it, but say so. Passing a whole aggregate is correct when the function
genuinely consumes most of it; the smell is one field used or pure
forwarding, not aggregation itself.

## Report

For each finding give file:line, the category, the wrong reading a
signature-only reader would plausibly form, and the concrete rename or
retype. Order by blast radius: exported signatures first, then internal
functions, then locals. A module whose signatures already explain themselves
is reported as clean — do not invent findings to fill a report.
