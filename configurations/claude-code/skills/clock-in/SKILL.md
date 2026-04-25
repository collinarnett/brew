---
name: clock-in
description: "Start a clocked work session in org-roam using emacs's real org-clock so it shows in the modeline. Use when the user wants to begin recording time for a work session; pairs with /timesheet to close the clock and append task descriptions later. Invoke with /clock-in or /clock-in <project-name>."
---

# Clock-in

Start an org-clock on today's project timesheet file so the conversation has an explicit start time and `/timesheet` can close the clock and attach task descriptions later.

## Invocation

- `/clock-in` — auto-detect project name from working directory
- `/clock-in <project>` — use the given project name

## Procedure

Follow these steps in order. Do not skip steps.

### 1. Determine the project name

If the user provided an argument, use it as the project slug (lowercase).

Otherwise, derive it from the current working directory basename. If the basename is generic (`src`, `repo`, `code`, `project`, `work`), use the parent directory name instead. Lowercase the result and strip any leading/trailing hyphens.

If the result is still ambiguous or too generic, ask the user.

### 2. Get the current time

Run:

```bash
date '+%Y-%m-%d %a %H:%M'
```

Capture the three fields as `DATE` (`YYYY-MM-DD`), `DAY` (3-letter weekday), and `TIME` (`HH:MM`). Together they form the **clock-in stamp** — the value `/timesheet` uses to find this exact session heading later.

### 3. Clock in via emacs

```bash
emacsclient -e "(brew/clock-in \"$PROJECT\" \"$DATE\" \"$DAY\" \"$TIME\")"
```

`brew/clock-in` (defined in `~/brew/configurations/emacs/emacs.el`):

- creates `~/org/roam/{project}_{YYYY}_{MM}_{DD}.org` via `org-roam-capture-` if missing,
- appends a `** session HH:MM` heading under `* Timesheet`,
- sets the heading's `:CLOCK_IN:` property to `DATE DAY TIME` so `/timesheet` can find this exact heading,
- calls `(org-clock-in)` so the modeline reflects the running clock,
- saves the buffer and returns the absolute file path.

Multiple Claude conversations can call `/clock-in` independently — each gets its own `** session` heading. Emacs only tracks one active org-clock at a time, so a later `/clock-in` (from any session) automatically closes the previous session's CLOCK line. `/timesheet` handles both cases (still-active and already-closed) via `brew/clock-out`.

### 4. Emit the boundary marker

After the helper returns, print this exact line:

```
--- TIMESHEET STARTED at {DATE} {DAY} {TIME} ---
```

Use the timestamp from step 2 verbatim (same three fields, same spacing). `/timesheet` reads this marker to know where this session began and which session heading to clock out and attach tasks under.

## Assumptions

- The emacs daemon is running (`emacsclient` reaches it). Same assumption as `/timesheet` and `/recap`.
- `org-roam-directory` is configured (it is, in `emacs.el`).
- The user has not manually clocked in elsewhere in a way that should not be disturbed — `org-clock-in` will close any active clock before opening this one.
