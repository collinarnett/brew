---
name: timesheet
description: "Generate org-roam timesheet entries from the current conversation. Use when the user wants to log time, create a timesheet entry, or record what was accomplished during a work session. Invoke with /timesheet or /timesheet <project-name> to override the auto-detected project. If the conversation contains a `--- TIMESHEET STARTED at ... ---` marker from `/clock-in`, this run closes that org-clock and nests task descriptions under the existing session heading instead of creating new top-level headings."
---

# Timesheet

Generate an org-roam timesheet entry summarizing the work done in the current conversation.

## Invocation

- `/timesheet` — auto-detect project name from working directory
- `/timesheet <project>` — use the given project name

## Procedure

Follow these steps in order. Do not skip steps.

### 1. Determine the time boundary

Scan the conversation for the most recent of these two markers:

- `--- TIMESHEET LOGGED at {timestamp} ---` — written by a previous `/timesheet` invocation; marks the **end** of the previous window.
- `--- TIMESHEET STARTED at {timestamp} ---` — written by `/clock-in`; marks the **start** of an explicit session and means an emacs org-clock is currently open against a `** session` heading.

The most recent of the two anchors the window. If a `STARTED` marker is the most recent, this run will close that open clock and attach tasks under its session heading (clock-in flow, see step 5b). If a `LOGGED` marker is the most recent, summarize work after it as new top-level headings (default flow, step 5a). If neither marker exists, summarize the entire conversation in the default flow.

### 2. Determine the project name

If the user provided an argument, use it as the project slug (lowercase).

Otherwise, derive it from the current working directory basename. If the basename is generic (`src`, `repo`, `code`, `project`, `work`), use the parent directory name instead. Lowercase the result and strip any leading/trailing hyphens.

If the result is still ambiguous or too generic, ask the user.

### 3. Get the current time

Run:

```bash
date '+%Y-%m-%d %a %H:%M'
```

This gives you the end time for the CLOCK entry. The start time is, in priority order:

1. The timestamp from the most recent `TIMESHEET STARTED` marker (clock-in flow), or
2. The timestamp from the previous `TIMESHEET LOGGED` marker, or
3. The earliest timestamp visible in the conversation (from tool results, file operations, git output, etc.)

If timestamps span multiple days, create separate CLOCK entries per day or per logical work block. (In the clock-in flow the CLOCK is already a single span owned by the session heading — multi-day spans should be rare; if they occur, clock out and start a new `/clock-in` per day.)

### 4. Summarize the work

Review the conversation (from the boundary in step 1 to now) and group the work into logical tasks. For each task:

- Write a short heading (5-10 words, lowercase, descriptive)
- Write 1-3 sentences describing what was accomplished
- Reference modified files using org tilde formatting: `~path/to/file~`
- Be concrete and specific — name functions, modules, and behaviors changed

#### Recover compacted history

The visible context only contains the *post-compaction* summary of any earlier work — short, lossy, and missing the concrete file/commit details you need for a good timesheet entry. If the user mentions compaction, or if you see `<command-name>/compact</command-name>` or "This session is being continued from a previous conversation" markers in the conversation, you MUST recover the full history before summarizing.

The conversation jsonl lives at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, where the encoded cwd replaces `/` with `-` (e.g. `/home/foo/bar` → `-home-foo-bar`). The session id matches the conversation file modified most recently in the matching project directory.

Use the jsonl plus `git log --since="<window-start>"` to reconstruct the actual work. Concretely:

1. Find the project dir: `ls -dt ~/.claude/projects/-${PWD//\//-}*/ | head -1` (or whatever encoding matches the cwd).
2. Find the active jsonl: `find <project-dir> -maxdepth 1 -name "*.jsonl" -newermt "<window-start>" | sort | tail -1`.
3. Extract real user messages (filter out tool results, system reminders, and compaction summaries) to recover the original asks.
4. Run `git log --since="<window-start>" --pretty=format:'%h %ai %s'` to enumerate commits made in the window — each commit is a concrete unit of work to account for.
5. For each commit, run `git show --stat <sha>` to get the actual files changed and the commit body, which feeds the task description.

Cross-check the commit list against your task groupings — if the commits cover work you don't have a logbook entry for, that work was hidden by compaction and needs an entry.

If the user asks about "all conversations" related to a project, also search sibling project directories under `~/.claude/projects/` for jsonls modified in the window, and `grep -l "<project-keyword>"` to find conversations from other working directories that touched the same project.

### 5. Write the org-roam file

The target file is `~/org/roam/{project}_{YYYY}_{MM}_{DD}.org` where the date is today's date (from step 3).

Branch on whether a `TIMESHEET STARTED` marker is the most recent boundary marker (step 1):

- **Clock-in flow** (STARTED marker present and more recent than any LOGGED marker): go to **step 5b**.
- **Default flow** (no STARTED marker, or a later LOGGED marker supersedes it): go to **step 5a**.

#### 5a. Default flow — top-level task headings

**If the file already exists:** Read it with the Read tool. Append new `**` task headings at the end of the file (after the last existing content). Do not overwrite or duplicate existing entries. Use the Edit tool to append.

**If the file does not exist:** Generate a UUID with `uuidgen` and create the file with this exact structure:

```
:PROPERTIES:
:ID:       {uuid}
:END:
#+title: {Project} {YYYY-MM-DD}

* Timesheet
** {task heading}
:LOGBOOK:
CLOCK: [{start-date} {start-day} {start-time}]--[{end-date} {end-day} {end-time}] =>  {H:MM}
:END:

{Description paragraph.}
```

Format rules:
- Title uses capitalized project name and dashes in the date: `#+title: Myproject 2026-04-07`
- Filename uses underscores: `myproject_2026_04_07.org`
- Day abbreviations are 3 letters: Mon, Tue, Wed, Thu, Fri, Sat, Sun
- Duration format is `H:MM` with two spaces before the `=>` and two spaces after
- CLOCK lines have no leading spaces
- Descriptions are plain prose, hard-wrapped around 70 characters
- File paths in descriptions use org tilde formatting: `~config.py~`

#### 5b. Clock-in flow — nest tasks under the existing session heading

The session heading and its open `CLOCK: [start]` line already exist in the file (created by `/clock-in`). The window may overlap with other Claude conversations that ran their own `/clock-in` for the same or different projects, so do not assume the clock is still active — let the helper decide.

Extract the start stamp from the most recent `--- TIMESHEET STARTED at {DATE} {DAY} {TIME} ---` marker (these three fields, exact spacing). That string is the heading's `:CLOCK_IN:` property value.

Close the clock and locate the file:

```bash
FILE=$(emacsclient -e "(brew/clock-out \"$PROJECT\" \"$STAMP\")" | tr -d '"')
```

`brew/clock-out` (in `~/brew/configurations/emacs/emacs.el`):
- finds the `~/org/roam/{project}_*.org` file containing `:CLOCK_IN: $STAMP`,
- if that heading is the currently-active org-clock, calls `org-clock-out` (writes the `--[end]` half and computed duration into the existing CLOCK line),
- if the clock has already been closed (because a later `/clock-in` from another conversation took over), no-op on the clock,
- saves the buffer and returns the absolute file path.

Read `$FILE`. Find the `** session HH:MM` heading whose `:CLOCK_IN:` property matches `$STAMP`. Append child task headings under it — one `***` per logical task — with prose descriptions. **No `:LOGBOOK:` on children**: the parent session heading owns the wall clock for the whole window.

Resulting structure under the matched session:

```
** session 14:30
:PROPERTIES:
:CLOCK_IN: 2026-04-25 Sat 14:30
:END:
:LOGBOOK:
CLOCK: [2026-04-25 Sat 14:30]--[2026-04-25 Sat 15:45] =>  1:15
:END:
*** {task heading}
{description paragraph}

*** {task heading}
{description paragraph}
```

Append the children just before the next `**` sibling heading (or at end-of-file if none follows). Same prose rules as step 5a apply: lowercase task headings of 5–10 words, 1–3 sentences, file paths in `~tilde~` formatting.

### 6. Sync org-roam

Run:

```bash
emacsclient -e '(org-roam-db-sync)'
```

### 7. Emit the boundary marker

After everything is written and synced, print this exact line:

```
--- TIMESHEET LOGGED at {YYYY-MM-DD HH:MM} ---
```

Use the same timestamp from step 3. This marker allows subsequent `/timesheet` invocations in the same conversation to know where to start.

### 8. Print a one-sentence summary

After the boundary marker, output a single sentence that summarizes the entire window's work. This is what the user will paste into an external/online timesheet, so it must stand alone — no headers, no bullets, no markdown, just one prose sentence that names the concrete things accomplished. Lead with the verb, list the work in commit-message style, end with a period.

## Example output — default flow (no `/clock-in`)

```org
:PROPERTIES:
:ID:       a1b2c3d4-e5f6-7890-abcd-ef1234567890
:END:
#+title: Myproject 2026-04-07

* Timesheet
** refactored authentication module
:LOGBOOK:
CLOCK: [2026-04-07 Mon 09:30]--[2026-04-07 Mon 11:45] =>  2:15
:END:

Extracted token validation from ~auth/middleware.py~ into a standalone
~auth/tokens.py~ module. Updated all call sites in ~api/routes.py~ and
~api/admin.py~ to use the new import path. Added type annotations to
the public interface.

** fixed flaky integration test
:LOGBOOK:
CLOCK: [2026-04-07 Mon 11:45]--[2026-04-07 Mon 12:10] =>  0:25
:END:

The ~test_concurrent_writes~ test was failing intermittently due to a
race condition in the test fixture teardown. Added explicit cleanup
ordering in ~tests/conftest.py~.
```

## Example output — clock-in flow (`/clock-in` then `/timesheet`)

```org
:PROPERTIES:
:ID:       a1b2c3d4-e5f6-7890-abcd-ef1234567890
:END:
#+title: Myproject 2026-04-07

* Timesheet
** session 09:30
:PROPERTIES:
:CLOCK_IN: 2026-04-07 Mon 09:30
:END:
:LOGBOOK:
CLOCK: [2026-04-07 Mon 09:30]--[2026-04-07 Mon 12:10] =>  2:40
:END:

*** refactored authentication module
Extracted token validation from ~auth/middleware.py~ into a standalone
~auth/tokens.py~ module. Updated all call sites in ~api/routes.py~ and
~api/admin.py~ to use the new import path.

*** fixed flaky integration test
The ~test_concurrent_writes~ test was failing intermittently due to a
race condition in the test fixture teardown. Added explicit cleanup
ordering in ~tests/conftest.py~.
```
