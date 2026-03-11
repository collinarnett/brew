---
name: git-surgical-staging
description: "Stage specific lines or hunks from files into git commits, enabling modular atomic commits instead of whole-file staging. Use this skill whenever the user asks to commit only part of a file, split changes across multiple commits, make atomic/granular/modular commits, stage specific lines or hunks, or when you need to commit logically distinct changes separately. Also use this when the user says things like 'commit the refactor separately from the bugfix', 'only commit the changes to function X', 'split this into separate commits', or references magit-style partial staging. If you are about to run `git add <entire-file>` but the file contains changes serving different purposes, stop and use this skill instead."
---

# Git Surgical Staging

This skill enables line-level git staging — the same technique Emacs magit uses when you select a region within a hunk and press `s`. It lets you create clean, atomic commits from a working tree that contains intermixed changes, without any external tools beyond git itself.

## Core technique

Every tool that supports line-level staging (magit, lazygit, gitui, VS Code) uses the same underlying mechanism: construct a filtered unified diff patch and apply it to the index via `git apply --cached`. You will do this directly.

The reason `git add -p` is insufficient is that it only operates at hunk granularity and requires interactive input. The reason `git add <file>` is insufficient is that it stages everything. The `git apply --cached` technique lets you stage arbitrary lines non-interactively.

## Planning phase

Before touching the index, plan the full sequence of commits. This prevents dependency violations and wasted rework.

### 1. Read every diff

Run `git diff` (all files) and read the full output. Do not skip files or skim — you need to understand every change to group them correctly.

### 2. Identify logical groups

Each group should be a single coherent concern: one feature, one bugfix, one refactor. A file may contribute lines to multiple groups. An overlay entry and the package it references are the same group.

### 3. Order groups by dependency

If group B references something introduced by group A (a function, a file, an import, an overlay entry), then A must be committed before B. Walk through each group and ask: "does this reference anything that doesn't exist in the tree yet?" If yes, the group that introduces it must come first.

### 4. Verify the plan

For each commit in order, mentally check: "if I checked out the tree at this commit, would it be internally consistent?" Every import must resolve, every reference must exist. If not, reorder or merge groups.

## Staging workflow

### Step 1: Construct a filtered patch

Save the full diff to a temporary file:

```bash
git diff -- <file> > /tmp/staging.patch
```

Then edit the patch to keep only the changes you want to stage. The rules are:

| Line type | Want to stage it? | Action |
|-----------|-------------------|--------|
| `+` line (addition) | Yes | Keep it |
| `+` line (addition) | No | **Delete the entire line** from the patch |
| `-` line (removal) | Yes | Keep it |
| `-` line (removal) | No | **Change the `-` prefix to a space** (makes it a context line) |
| ` ` line (context) | N/A | Always keep |
| `\ No newline...` | N/A | Always keep |

Do not modify the `diff --git`, `index`, `---`, or `+++` header lines.

Do not worry about the `@@ -X,Y +A,B @@` hunk header line counts — the `--recount` flag will fix them.

If an entire hunk has no remaining `+` or `-` lines after filtering, delete the entire hunk (header and all its lines).

### Step 2: Apply the filtered patch to the index

```bash
git apply --cached --recount /tmp/staging.patch
```

This stages only the selected changes without touching the working tree. The `--recount` flag recalculates hunk header counts, so you don't need to compute them manually.

### Step 3: Verify before committing

```bash
git diff --cached -- <file>   # Shows what will be committed
git diff -- <file>            # Shows what remains unstaged
```

**Read the staged diff line by line.** Do not just check file names — verify the actual content. Check that:

- Every reference (import, function call, file path) points to something that already exists in the tree
- No unrelated changes leaked into this commit
- The staged change is self-contained and coherent

### Step 4: Commit and repeat

```bash
git commit -m "<message describing this logical change>"
```

Then go back to step 1 for the next group. Repeat until the working tree is clean or all logical groups are committed.

## Example

Starting diff:

```
diff --git a/app.py b/app.py
index abc1234..def5678 100644
--- a/app.py
+++ b/app.py
@@ -1,8 +1,10 @@
+import logging
+
 def process(data):
-    result = data.split(",")
+    result = data.strip().split(",")
     return result

 def format_output(result):
-    return str(result)
+    return json.dumps(result)
```

This diff has two unrelated changes: adding `import logging` + fixing `process()`, and changing `format_output()`. To commit them separately:

**First commit** — stage only the `process()` fix and the import:

Edit the patch to exclude the `format_output` change. Delete the `+    return json.dumps(result)` line entirely, and convert `-    return str(result)` to a context line by replacing the `-` prefix with a space:

```
diff --git a/app.py b/app.py
index abc1234..def5678 100644
--- a/app.py
+++ b/app.py
@@ -1,8 +1,10 @@
+import logging
+
 def process(data):
-    result = data.split(",")
+    result = data.strip().split(",")
     return result

 def format_output(result):
     return str(result)
```

```bash
git apply --cached --recount /tmp/staging.patch
git commit -m "fix: strip whitespace before splitting in process()"
```

**Second commit** — the remaining `format_output()` change is the only unstaged change:

```bash
git add app.py
git commit -m "refactor: use json.dumps in format_output()"
```

## Shortcut: filterdiff for hunk-level staging

When changes are cleanly separated into different hunks (not intermixed within a single hunk), you can use `filterdiff` from the `patchutils` package if available:

```bash
# See which hunks exist
git diff -- <file> | grep -n '^@@'

# Stage only hunks 1 and 3
git diff -- <file> | filterdiff --hunks=1,3 | git apply --cached

# Stage hunks matching a regex pattern
git diff | grepdiff --output-matching=hunk "function_name" | git apply --cached
```

This is simpler when it applies, but cannot split within a hunk.

## Multi-file staging

When changes span multiple files:

1. **Whole files serve one purpose**: just `git add <file1> <file2>`.
2. **A file has mixed changes**: use the patch technique on that file, `git add` the clean ones normally.

You can also filter a multi-file diff by file:

```bash
git diff -- file1.py file2.py | git apply --cached
```

## When to use this

Use surgical staging instead of `git add <file>` whenever:

- A file contains changes that serve different purposes (refactor + feature + bugfix)
- The user asks for atomic, modular, or granular commits
- You're about to `git add .` but the changes are logically mixed
- The user references magit, partial staging, or line-level staging

Do NOT use surgical staging when:

- All changes in a file serve one purpose — just `git add <file>`
- The user explicitly wants everything in one commit
- It's a WIP/checkpoint commit where atomicity doesn't matter
