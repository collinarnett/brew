---
name: recap
description: "Summarize past Claude Code and Codex conversations across all projects into an org-roam note. Invoke with /recap (yesterday), /recap today, /recap YYYY-MM-DD, or /recap YYYY-MM-DD..YYYY-MM-DD."
---

# Recap

Summarize work done in prior agent conversations — both Claude Code (`~/.claude/projects/`) and Codex (`~/.codex/sessions/` plus any per-project `<project>/.codex/sessions/`) — across every project, then write the result to an org-roam node so it survives and is searchable alongside daily notes.

## Invocation

- `/recap` — yesterday (local timezone)
- `/recap today`
- `/recap yesterday`
- `/recap 2026-04-10` — a specific date
- `/recap 2026-04-01..2026-04-07` — inclusive range

## Procedure

### 1. Parse the argument and compute date bounds

Resolve the argument to `START_DATE` and `END_DATE` (YYYY-MM-DD, local TZ).

- empty or `yesterday` → `date -I -d yesterday`
- `today` → `date -I`
- `YYYY-MM-DD` → that day for both
- `A..B` → `A` and `B`; error if `B < A` or span > 31 days

Convert to UTC ISO bounds for jq filtering (session timestamps are UTC with `Z`):

```bash
START_ISO=$(date -u -d "$START_DATE 00:00" +%FT%TZ)
END_ISO_EXCL=$(date -u -d "$END_DATE 00:00 + 1 day" +%FT%TZ)
RANGE_LABEL="$START_DATE"
[ "$START_DATE" != "$END_DATE" ] && RANGE_LABEL="${START_DATE}..${END_DATE}"
```

### 2. Skip if the note already exists

Before triaging or summarizing anything, check whether this range already has a recap note and exit early if so. Subagent fan-out is the expensive step; don't run it just to throw away the output.

```bash
SLUG=${RANGE_LABEL//../_to_}
EXISTING=$HOME/org/roam/recap-$SLUG.org
if [ -f "$EXISTING" ]; then
  echo "--- RECAP $RANGE_LABEL ---"
  echo "Recap already exists at $EXISTING"
  exit 0
fi
```

This makes same-day re-runs (manual re-invocations, timer retries after a missed `Persistent=true` catch-up) effectively free.

### 3. Enumerate and triage sessions

```bash
recap-triage "$START_ISO" "$END_ISO_EXCL"
```

Emits one TSV row per session with in-range content. Columns:

```
source  cwd  first_ts  last_ts  records  user_turns  preview  path
```

`recap-triage` handles all the plumbing: globs `~/.claude/projects/*/*.jsonl`, finds every `.codex/sessions` root under `$HOME`, runs one duckdb query per schema, and emits per-file aggregates. One invocation replaces the old find+jq loops.

### 4. Drop trivial sessions

Use judgment on each TSV row before spawning subagents:

- `user_turns == 0` → drop silently (nothing substantive in range).
- `user_turns <= 2` and `preview` is a single slash command (`/recap`, `/timesheet`, `/tasks`, etc.) or under 20 chars → drop as trivial.
- Multiple rows in the same `cwd` with near-identical short `preview` (e.g. test probes like "Return JSON with word=hello") → collapse into a single "N automated probes" line without spawning a subagent.

Count drops for the summary. The remaining rows are the survivors for step 5.

### 5. Fan out subagents in parallel

For each surviving row from step 4, launch one `general-purpose` Agent in parallel (send multiple Agent calls in a single assistant message; batch in groups of 8 if there are many). Use the prompt template matching the `source` column (`claude` or `codex`), substituting `{JSONL_PATH}` with the `path` column and `{START_ISO}`, `{END_ISO_EXCL}` with the date bounds from step 1.

**Claude prompt:**

```
Summarize the Claude Code session at {JSONL_PATH}, restricted to records
with .timestamp in [{START_ISO}, {END_ISO_EXCL}).

Slice with:
  jq -c 'select(.timestamp >= "{START_ISO}" and .timestamp < "{END_ISO_EXCL}")' {JSONL_PATH}

For user records (.type=="user"): take .message.content (string or array;
skip tool_result blocks — those are tool output, not user intent).
For assistant records (.type=="assistant"): .message.content is always an
array — take text blocks and note tool_use names + first-line arg summary.
Skip: attachment, file-history-snapshot, system, permission-mode, custom-title.

Do NOT read CLAUDE.md. Do NOT explore the filesystem. Work only from the jsonl.

Capture .cwd from the first in-range record with a cwd field. Compute local
time of the first and last in-range record — use `date -d` on the ISO timestamp.

Return exactly this, nothing else:

### <cwd basename> [claude] — <HH:MM>-<HH:MM>
- 3-8 bullets: what was attempted, what worked, what failed, key decisions
- Files touched: ~path/a~, ~path/b~ (max 10, org tilde format)
- Outcome: completed | abandoned | ongoing

Under 200 words. No preamble, no closing summary.
```

**Codex prompt:**

```
Summarize the Codex session at {JSONL_PATH}, restricted to records with
.timestamp in [{START_ISO}, {END_ISO_EXCL}).

Slice with:
  jq -c 'select(.timestamp >= "{START_ISO}" and .timestamp < "{END_ISO_EXCL}")' {JSONL_PATH}

Schema:
- .type=="session_meta" carries .payload.cwd and .payload.model_provider.
- .type=="response_item" carries .payload.role (user/assistant/developer)
  and .payload.type (message, agent_message, agent_reasoning, function_call,
  function_call_output, reasoning, user_message, token_count).

For user content (.payload.role=="user"): extract
  .payload.content[] | select(.type=="input_text") | .text
  Skip messages starting with "# AGENTS.md" or "<environment_context>" —
  those are bootstrap noise injected by Codex, not real user intent.
For assistant content (.payload.role=="assistant" or .payload.type=="agent_message"):
  extract text blocks similarly. Note function_call entries (tool name + brief
  arg summary).
Skip: token_count, reasoning, agent_reasoning bodies (reasoning is internal),
function_call_output (just echoes tool output).

Do NOT read AGENTS.md. Do NOT explore the filesystem. Work only from the jsonl.

Capture .payload.cwd from the session_meta record (first record). Compute local
time of the first and last in-range response_item — use `date -d`.

Return exactly this, nothing else:

### <cwd basename> [codex] — <HH:MM>-<HH:MM>
- 3-8 bullets: what was attempted, what worked, what failed, key decisions
- Files touched: ~path/a~, ~path/b~ (max 10, org tilde format)
- Outcome: completed | abandoned | ongoing

Under 200 words. No preamble, no closing summary.
```

### 6. Assemble the body

Concatenate subagent outputs. Group by `cwd` basename (sessions in the same project render under one subheading; the `[claude]` / `[codex]` tag in each session header preserves source). Prepend:

```
* Summary
<one paragraph: N sessions across M projects, dominant themes, K trivial sessions skipped>

* Sessions
```

Write the assembled body to a tempfile under `$HOME` (not `/tmp`):

```bash
BODY=$(mktemp -p "$HOME/.cache" --suffix=.org claude-recap-XXXXXX)
```

`/tmp` is not safe here: when the recap is invoked from a systemd service (e.g. via `/schedule` or `/loop`), the harness shell runs under `PrivateTmp=yes`, so the emacs daemon — which has its own `/tmp` — cannot see the file. Keep the body inside `$HOME`, which both sides share.

Use the Write tool to populate `$BODY`.

If there are **zero** surviving sessions, print `No substantive sessions in $RANGE_LABEL` and stop — do not create a note.

### 7. Create the org-roam node via emacs

```bash
FILE=$(emacsclient -e "(brew/create-recap-note \"$RANGE_LABEL\" \"$BODY\")" | tr -d '"')
rm "$BODY"
echo "Created $FILE"
```

The helper `brew/create-recap-note` (defined in `~/brew/configurations/emacs/emacs.el`) uses `org-roam-capture-` with `:immediate-finish t`, which:
- creates the file at `~/org/roam/recap-<RANGE_LABEL>.org` (with `..` replaced by `_to_` for ranges),
- assigns a fresh `:ID:` via `org-id-new`,
- registers the node with org-roam's db via the autosync hook.

If the file already exists, the helper returns the existing path without clobbering.

### 8. Emit the boundary marker

Print this exact line so repeated `/recap` invocations in the same conversation are idempotent:

```
--- RECAP $RANGE_LABEL ---
```

## Assumptions

- The emacs daemon is running (`emacsclient` reaches it). Same assumption as `/timesheet`.
- `recap-triage` is on `$PATH` (installed via brew's `pkgs/recap-triage`).
- Today's date comes from the system clock; no timezone override.
