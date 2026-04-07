---
name: timesheet
description: "Generate org-roam timesheet entries from the current conversation. Use when the user wants to log time, create a timesheet entry, or record what was accomplished during a work session. Invoke with /timesheet or /timesheet <project-name> to override the auto-detected project."
---

# Timesheet

Generate an org-roam timesheet entry summarizing the work done in the current conversation.

## Invocation

- `/timesheet` — auto-detect project name from working directory
- `/timesheet <project>` — use the given project name

## Procedure

Follow these steps in order. Do not skip steps.

### 1. Determine the time boundary

Scan the conversation for the most recent `--- TIMESHEET LOGGED at {timestamp} ---` marker. If found, only summarize work done **after** that marker. If no marker exists, summarize the entire conversation.

### 2. Determine the project name

If the user provided an argument, use it as the project slug (lowercase).

Otherwise, derive it from the current working directory basename. If the basename is generic (`src`, `repo`, `code`, `project`, `work`), use the parent directory name instead. Lowercase the result and strip any leading/trailing hyphens.

If the result is still ambiguous or too generic, ask the user.

### 3. Get the current time

Run:

```bash
date '+%Y-%m-%d %a %H:%M'
```

This gives you the end time for the CLOCK entry. The start time is either:
- The timestamp from the previous `TIMESHEET LOGGED` marker, or
- The earliest timestamp visible in the conversation (from tool results, file operations, git output, etc.)

If timestamps span multiple days, create separate CLOCK entries per day or per logical work block.

### 4. Summarize the work

Review the conversation (from the boundary in step 1 to now) and group the work into logical tasks. For each task:

- Write a short heading (5-10 words, lowercase, descriptive)
- Write 1-3 sentences describing what was accomplished
- Reference modified files using org tilde formatting: `~path/to/file~`
- Be concrete and specific — name functions, modules, and behaviors changed

### 5. Write the org-roam file

The target file is `~/org/roam/{project}_{YYYY}_{MM}_{DD}.org` where the date is today's date (from step 3).

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

## Example output file

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
