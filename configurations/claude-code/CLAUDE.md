# Memory

Persist information to auto-memory for things specific to the current project. For brew-specific or cross-project knowledge, add it to this file instead so it applies everywhere.

# Approach

## Check Real State First
Always inspect the live environment, actual config files, and real data before answering. Never speculate from cached knowledge or memory. When asked about paths, secrets, infrastructure state, or data — trace them precisely rather than guessing.

## When Corrected, Fix Everything
When the user corrects your approach, apply the fix to ALL affected locations across the repo, not just the immediate spot. Do not circle back to a rejected approach.

## Design Decisions Conform to the Principles and Skills
Every design decision — new code, refactors, and recommendations alike — must conform to the Software Engineering Design Principles in this file and to the review skills under configurations/claude-code/skills/. Check a proposal against both before presenting it: one that reverses a confirmed review finding or makes an invalid state representable again is wrong even when it improves another metric, such as line count or the number of types. When principles pull in opposite directions, name the tension and resolve it by deepening the domain model rather than dropping a principle.

## No Shortcuts
No blanket ruff ignores, no `type: ignore` comments, no `or []` defaults to silence errors. Read project config files (`pyproject.toml`, `flake.nix`, etc.) before proposing solutions. This rule persists under pressure — when a build fails, a hardening directive misbehaves, or a CLI seems to need a TTY, fix it at the right layer (correct option type, real flag, documented helper). Do not invent workarounds, hand-install files into system dirs, `bash -lc` PATH tricks, `script -qc` TTY shims, or any other "just to make it work" hack. When the proper path isn't obvious, look it up (NixOS manual, home-manager options, upstream source) or ask.

## Never Hot-Reload the Running Emacs
Never load new or changed elisp into the user's running emacs daemon — no `emacsclient -e '(load ...)'`, no re-evaluating defuns, no adding advice at runtime. Apply emacs config changes by editing `configurations/emacs/emacs.el` in brew and deploying with `clan machines update <host>`; verify through the deploy. Read-only emacsclient queries for diagnosis are fine.

## Prefer MCP Tools Over Shelling Out
When an MCP tool is available for the operation (clan, git, github, nixos, etc.), use it via the tool call interface rather than invoking the CLI through Bash. Shell out only when there is no MCP equivalent (systemctl, emacsclient, arbitrary scripts). Loading the MCP tool via ToolSearch and calling it is the preferred path — not `Bash("clan machines update ...")`, `Bash("gh pr view ...")`, or similar when the MCP server already exposes the operation.

## Nix Conventions
When working in Nix repos: always use Nix-idiomatic approaches and clan-native tooling first. Do not use `uvx`, `pip`, `npx`, or non-Nix package managers. When stuck on Nix packaging, read the Nix manual or use the NixOS MCP server before trying hacks. Prefer simple solutions (symlinks, writeShellApplication) over complex workarounds (patching package.json, mainProgram overrides). Use `with pkgs;` when listing packages in Nix expressions to keep lists clean.

Do not auto-wire new packages into `flake.checks`. Adding a derivation to `pkgs/` and registering it in the overlay is enough; the user opts into `flake.checks` derivations manually when they want them. Never propose or default to creating one.

Common tools like `python3`, `jq`, etc. are not in `$PATH` by default on NixOS. Use `nix shell nixpkgs#<pkg> -c <cmd>` or `nix run nixpkgs#<pkg>` to access them ad hoc. Prefer the new Nix CLI (`nix build`, `nix shell`, `nix run`, `nix develop`, `nix eval`) over legacy commands (`nix-build`, `nix-shell`, `nix-env`).

# Software Engineering Design Principles

## Core Philosophy

### Parse, Don't Validate
Resolve raw inputs into typed objects at the boundary. Functions deep in the stack should never receive strings that might be invalid. No `or []` shortcuts, no empty strings as None alternatives. Invalid states should be unrepresentable at the type level.

### Configuration Over Environment Variables
Programs read their settings from their configuration file, never from environment variables — env vars are invisible inputs that nothing records or validates. Secrets enter configuration as *paths to files* holding the secret (what clan vars, sops, or systemd credentials render, or a file written by hand), never as inline values: inline secrets end up committed in dotfiles or rendered world-readable into the Nix store. Resolve every configured path once at load into a proven type; a path that does not deliver fails the run naming the field. Nix module options for secret files are `types.str`, which rejects the path literal that would copy the secret into the store.

### Declarative Over Imperative
Models describe themselves (`__str__`). Tool registration via decorators. Configuration via Pydantic. Derive patterns from what the code already does rather than imposing new abstractions.

### Use Your Dependencies
Before writing new code, check if a dependency already solves the problem. Don't create formatters, registries, or validation layers when the framework already provides them.

### Fix Root Causes, Not Symptoms
Don't use `or []` to hide missing values — surface the actual error. Don't use retry loops to work around timeouts — configure the timeout correctly. Don't add restart commands — make the service not die.

### Solve the Class, Not the Case
A fix that handles the input in front of you and nothing else is not a fix. When a case defeats the current approach, find the property that separates the cases and encode that, so every future input of the same kind is handled by construction. Special-casing the failing input, hardcoding its identifier, or resolving it by hand outside the program are all the same mistake wearing different clothes: the work does not survive the next input.

The bar is what the program can do unaided, never what you can figure out. Determining the answer through your own investigation and then writing it into the code as a constant is a report on one input, not a capability. If a human can determine the answer from the data available, the program can be made to determine it from the same data; find the signal they used and implement that.

## Architecture

### Onion Architecture
Pure core inside (models, config, constants), I/O adapters around it (auth, clients, infrastructure), services orchestrating them, presentation on the outside (CLI, TUI, MCP). Inner layers never import from outer layers.

### Put Logic Where It Belongs
Not where it's convenient. If both presentation layers use it, it goes in the services layer, not in either presentation layer.

### Push Logic Toward the Pure Core
The onion has a size rule as well as a direction rule: as much of the program as possible belongs in the innermost layer, where functions take data and return data. Effects belong at the edges, and an effectful function that computes something should be split into a pure function that computes it and a thin caller that supplies the input and writes the output. The pure core is the part that can be tested exhaustively, and a thick I/O layer wrapped around a thin core is the shape that makes a codebase untestable no matter how many tests are written against it.

Judge each layer by what it would take to test it. Operational concerns — connections, concurrency, configuration loading, process lifetime — are the outermost layer and stay small. Adapters to external services sit between. Everything that decides anything goes inside. This is Matt Parsons' three-layer cake, and it is the concrete allocation rule behind the onion: <https://www.parsonsmatt.org/2018/03/22/three_layer_haskell_cake.html>

### Client vs Service Distinction
A **client** wraps a single external API. A **service** orchestrates multiple clients to produce a business result. Don't create services for single-API-call operations.

### Share Code Between Presentation Layers
CLI, TUI, and MCP should call the same services. Never duplicate business logic in a presentation layer.

### Single Source of Truth
Constants, deployment mappings, URLs — defined once, imported everywhere. No hardcoded values scattered across files.

## Code Quality

### DRY
Deduplicate aggressively. If the same logic exists in two places, consolidate it.

### No Hacks
No bash restart loops, no workarounds. Solve problems at the right layer.

### Explicit Behavior
Functions should do what they say, nothing more. No hidden side effects. No implicit fallbacks that surprise the caller.

### Interfaces Do Not Hide Work
What a command does is what its name says, and every expensive or destructive step it performs is a step the user asked for. A verb that silently also acquires, converts, uploads, or deletes is lying, and the user discovers the lie at the worst moment: when the hidden step fails, or when they wanted to run the later stage alone and find they cannot. Expensive stages get their own verbs, run in sequence, with each stage's output persisted so the next can start from it. Prompts follow the same rule — a menu that omits the option the user needs, or that presents a choice whose consequences are not visible in the menu, is hiding the same way.

### The Tool Is Self-Sufficient
A user holding only the tool can complete the task. If finishing requires consulting a wiki, running a second program by hand, reading a forum thread, or knowing a value that the tool could have discovered, the tool is unfinished. When weighing designs, reject any option whose usability depends on knowledge the tool does not surface, and prefer the option that puts the discovery inside the program.

### Diffs Justify Their Size
Volume is a cost the reader pays. A refactor that grows total line count, a fix that touches files unrelated to the fault, or a feature whose diff dwarfs the behaviour it adds needs a reason stated up front, before the diff is presented. Simplification work that adds lines has usually failed at something; say what and why rather than letting the number speak. Mechanical changes (formatting, renames, generated code) go in their own commit so the reviewable part stays small.

### Signatures and Names Must Self-Explain
A reader with only the function signature — type names and parameter names — must be able to tell what each argument is and why the function needs it. Never thread a grab-bag record (CLI flag bundles, "Common", "Opts") into functions that use one field of it: derive the precise value once at the boundary and pass a type named for what it answers. The same bar applies to parameter names: `progressStyle`, not `style`; `flaggedSource`, not `flagged`. If explaining an argument takes a sentence the name could have carried, rename it.

### Consistency
Similar operations should work the same way everywhere. Naming, structure, patterns should be predictable across the codebase.

### Comments Stand Alone
A code comment is read by someone who has only the code, never the conversation that produced it. State what is true of the code today and why, in absolute terms. Never reference removed components, prior approaches, or decisions from a conversation ("the previous X", "instead of the old Y", "stays enabled"), and never frame a comment as "X, not Y" or "should be X rather than Y" when the reader had no reason to expect Y. That contrast only lands for someone who saw the rejected alternative get discussed. State the positive fact and the reason.

### Comments Inform, They Never Defend
A comment earns its place by telling that reader something the code cannot: an external constraint, the consequence of getting it wrong, or a line that looks removable but is load-bearing. Do not justify a choice, pre-empt an objection, or record why some other approach was rejected. Nobody reading the line is asking, and a self-contained sentence is still noise if it exists only to defend the code from review. Keep that reasoning in the commit message.

## Testing

### Tests Must Be Able to Fail
A test written by the same pass that wrote the code tends to assert the shape of what was just built, so it passes forever and detects nothing. Before adding a test, name the bug it would catch and confirm the test fails when that bug is present — break the implementation, watch it go red, restore it. A test whose failure mode you cannot state does not belong in the suite.

Default to properties and golden files. Reach for a hand-written example test only to pin a specific bug that was actually observed, and name that bug in the test.

### Derive Properties Systematically
"Write property tests" is not a plan. Work through the five sources of properties from John Hughes' *How to Specify It!* (<https://research.chalmers.se/publication/517894/file/517894_Fulltext.pdf>) and record which ones apply and which do not:

1. **Invariants** — what stays true of every value the code produces.
2. **Postconditions** — what the output satisfies given the input.
3. **Metamorphic properties** — how the output changes when the input changes in a known way. These are the highest-yield and the most often skipped.
4. **Algebraic laws** — identities, inverses, idempotence, commuting operations.
5. **Model-based** — the operation agrees with a simpler reference model.

Stateful interfaces get command-sequence testing against a model rather than one test per operation, so orderings nobody thought of are covered.

### Verify Against a Reference
When a reimplementation replaces an existing library or tool, correctness means agreeing with the original, and the only honest way to establish that is to run both over generated inputs and compare. Build the differential harness before porting behaviour, not after the bugs surface. A corpus of real files is a smoke test, not a specification — it samples the inputs somebody happened to collect and says nothing about the rules.

### Measure the Suite, Not the Coverage Percentage
Line coverage says the code ran, never that a mistake would have been caught. Mutation testing answers the real question by breaking the code deliberately and asserting the suite goes red; a surviving mutant is a proven gap. Treat surviving mutants as findings and either kill them with a test or record why the mutation is meaningless.

## Error Handling

### Predictable Errors, Short Timeouts
Every command should fail fast with a clear message. Never leave users waiting. 5 seconds for operations that should be instant.

### Surface, Don't Swallow
Don't catch exceptions and return empty results. If something fails, the caller should know.

## Process

### Verify After Actions
Run `git show HEAD` after committing. Run the actual command after changing it. Don't assume — verify.

### Mechanical Gates Come First
A rule a tool can check is not a rule to remember. Whenever a preference in this file can be expressed as a compiler flag, a lint rule, a formatter, or a test, express it there and let the gate be the enforcement. Reviews and audits are for the judgment calls that survive after the gates are green, and a finding a gate could have caught is a gate that was missing.

Haskell projects carry this baseline, and new ones start with it:

- `ghc-options: -Wall -Wcompat -Wincomplete-record-updates -Wincomplete-uni-patterns -Wpartial-fields -Wmissing-export-lists -Wmissing-deriving-strategies -Wredundant-constraints -Wunused-packages` in a `common` stanza every component imports.
- `-Werror` in `cabal.project`, never in the `.cabal` file. Development builds treat warnings as fatal; a released tarball built by someone else on a newer GHC must not break on a warning that GHC invented after the release.
- `-fwrite-ide-info` under `program-options` in `cabal.project`, so weeder and stan have HIE files. Setting an explicit `-hiedir` instead collides: the executable's `Main` and the test suite's `Main` write the same file, and weeder then reports the whole library as dead.
- `.hlint.yaml` restricting the partial and unsafe functions, extending the catalog at <https://github.com/NorfairKing/haskell-dangerous-functions>. `fromIntegral` is among them: it converts between any two number types, so a call site says nothing about which conversion is meant, and a narrowing one truncates in silence. The package gets one `Convert` module that the restriction exempts, holding a named function per conversion the code actually performs — `intCast` from `int-cast` where an instance proves the widening safe, `Data.Bits.toIntegralSized` where the conversion can fail and the caller handles it, and a clamping function whose haddock states the bound where the range is guaranteed by construction.
- `weeder.toml` for cross-module dead code, and `stan` for HIE-based anti-patterns.
- git-hooks.nix wiring formatter and linter into pre-commit from the flake.
- A mutation check where the test suite can support one. sydtest's `mutationCheck` is the Haskell implementation: it instruments the library through a GHC plugin, which is framework-agnostic, but its coverage phase runs the test binary with `--mutation-coverage-list`, which is a sydtest flag. A tasty suite builds instrumented and then fails that phase, so a project that wants mutation testing writes its tests with sydtest from the start.

An audit round ends by running the gates, never by declaring the findings fixed.

### Ship for Everyone
Anything that leaves this machine — a public repo, a tool published to others, a module in a shared codebase — works for someone who is not Collin, on hardware that is not azathoth. No hardcoded hostnames, home directories, usernames, keys, mount points, or paths into `~/brew`, and no dependency on services that only exist on this network. Secrets come from configuration the user supplies. A repo that cannot be cloned and built by a stranger is not finished, and self-containment beats deduplication when the two conflict across repository boundaries.

### Versioning Follows the Ecosystem
Use the versioning scheme the ecosystem expects, not a general-purpose habit. Haskell packages follow the PVP: versions are `A.B.C.D`, where `A.B` together are the major version that any breaking API change must bump, `C` covers additions, and `D` is for changes no dependent can observe. Dependency bounds follow from the same reading, so `>= 1.2 && < 1.3` is what pinning to a major version looks like.

### Reviews Verify Fixes, Never Assume Them
When briefing a reviewer (human, agent, or workflow) on code that was already partly fixed, describe what changed and have them verify it — never declare items settled or exclude them from scope. A partial fix hides perfectly behind an "already done" claim, and a refute-biased verifier fed the same claim will kill the finding twice.

### Atomic Commits
Each commit is one logical change. Use surgical staging when a file has mixed changes.

### Understand Before Refactoring
Read all related code. Understand existing patterns. Derive the right abstraction from what the code does, not from theory.

### Preserve Special Characters
Files may contain Private Use Area Unicode characters (e.g. Siji icons in waybar configs) that Claude cannot render or type. Never rewrite these files with Edit or Write — use `perl` with `\x{XXXX}` escapes or `sed` with hex byte sequences for surgical edits. Verify icons survive with `od -A x -t x1z <file> | grep 'ee 8'` before committing.

# Writing Style

When editing prose, match the existing voice of the document rather than imposing a generic style. Write in a direct, technical, human voice. Avoid these LLM tells:

**Words to avoid:** "delve", "dive into", "it's important to note", "certainly", "crucial", "pivotal", "bolstered", "underscore", "Additionally", "Furthermore", "Moreover", "multifaceted", "ascertain", "without further ado", "Let's unpack"

**Structural tells to avoid:**
- Excessive em dashes in casual contexts
- Constant "It's not X — it's Y" parallelism
- Uniform sentence length with no rhythm variation
- Overuse of bullet points where paragraphs would be better
- Chains of short declarative aphorisms: "We can't X what we can't Y. And Y requires Z."
- Colon-heavy titles/headers
- Arbitrary bolding without clear purpose
- Excessive hedging: "typically", "might be", "may"

**Content tells to avoid:**
- Generic/vague claims without specifics
- Empty summary sentences that feel conclusive but say nothing
- Forced metaphors that gesture at meaning without earning it
- Filler — multiple sentences reducible to one
- Unearned profundity: "Something shifted", "Everything changed"
- Chat-context references inside documents: contrastive corrections ("X is not Y — it's…"), "as noted earlier", clarifications meaningful only to someone who saw a prior draft. Documents are read standalone; readers don't have the transcript.

Prefer specificity, varied sentence length, natural voice, and concise expression.
