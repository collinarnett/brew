# Memory

Persist information to auto-memory for things specific to the current project. For brew-specific or cross-project knowledge, add it to this file instead so it applies everywhere.

# Approach

## Check Real State First
Always inspect the live environment, actual config files, and real data before answering. Never speculate from cached knowledge or memory. When asked about paths, secrets, infrastructure state, or data — trace them precisely rather than guessing.

## When Corrected, Fix Everything
When the user corrects your approach, apply the fix to ALL affected locations across the repo, not just the immediate spot. Do not circle back to a rejected approach.

## No Shortcuts
No blanket ruff ignores, no `type: ignore` comments, no `or []` defaults to silence errors. Read project config files (`pyproject.toml`, `flake.nix`, etc.) before proposing solutions.

## Nix Conventions
When working in Nix repos: always use Nix-idiomatic approaches and clan-native tooling first. Do not use `uvx`, `pip`, or non-Nix package managers. When stuck on Nix packaging, read the Nix manual or use the NixOS MCP server before trying hacks. Prefer simple solutions (symlinks, writeShellApplication) over complex workarounds (patching package.json, mainProgram overrides). Use `with pkgs;` when listing packages in Nix expressions to keep lists clean.

Common tools like `python3`, `jq`, etc. are not in `$PATH` by default on NixOS. Use `nix shell nixpkgs#<pkg> -c <cmd>` or `nix run nixpkgs#<pkg>` to access them ad hoc. Prefer the new Nix CLI (`nix build`, `nix shell`, `nix run`, `nix develop`, `nix eval`) over legacy commands (`nix-build`, `nix-shell`, `nix-env`).

# Software Engineering Design Principles

## Core Philosophy

### Parse, Don't Validate
Resolve raw inputs into typed objects at the boundary. Functions deep in the stack should never receive strings that might be invalid. No `or []` shortcuts, no empty strings as None alternatives. Invalid states should be unrepresentable at the type level.

### Declarative Over Imperative
Models describe themselves (`__str__`). Tool registration via decorators. Configuration via Pydantic. Derive patterns from what the code already does rather than imposing new abstractions.

### Use Your Dependencies
Before writing new code, check if a dependency already solves the problem. Don't create formatters, registries, or validation layers when the framework already provides them.

### Fix Root Causes, Not Symptoms
Don't use `or []` to hide missing values — surface the actual error. Don't use retry loops to work around timeouts — configure the timeout correctly. Don't add restart commands — make the service not die.

## Architecture

### Onion Architecture
Pure core inside (models, config, constants), I/O adapters around it (auth, clients, infrastructure), services orchestrating them, presentation on the outside (CLI, TUI, MCP). Inner layers never import from outer layers.

### Put Logic Where It Belongs
Not where it's convenient. If both presentation layers use it, it goes in the services layer, not in either presentation layer.

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

### Consistency
Similar operations should work the same way everywhere. Naming, structure, patterns should be predictable across the codebase.

## Error Handling

### Predictable Errors, Short Timeouts
Every command should fail fast with a clear message. Never leave users waiting. 5 seconds for operations that should be instant.

### Surface, Don't Swallow
Don't catch exceptions and return empty results. If something fails, the caller should know.

## Process

### Verify After Actions
Run `git show HEAD` after committing. Run the actual command after changing it. Don't assume — verify.

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

Prefer specificity, varied sentence length, natural voice, and concise expression.
