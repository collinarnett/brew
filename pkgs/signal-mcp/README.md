# signal-mcp

Signal message history and sending for MCP clients, on top of
[signal-cli](https://github.com/AsamK/signal-cli)'s daemon. signal-cli keeps no
message history, so this package records one.

One executable runs in three modes:

- `signal-mcp ingest` subscribes to the daemon's received messages and writes
  each one into a SQLite history. That includes messages the account sends
  from its other devices, along with edits, remote deletes and reactions.
  Run it as a long-lived service.
- `signal-mcp read` is an MCP server over the history. It opens the database
  with writes refused and never connects to signal-cli.
  - `signal_list_conversations` lists conversations, most recent first.
  - `signal_read_conversation` reads one conversation, newest first, paged by
    `before`.
  - `signal_search` runs a full-text search for messages containing every
    word.
  - `signal_find` finds people and groups by name.
- `signal-mcp send` is an MCP server with one tool, `signal_send`. It sends a
  text message to a conversation id and adds it to the history.

Disappearing messages are deleted from the history when their timer, counted
from the time they were sent, runs out. View-once messages are recorded without
their text or media.

The history begins when the ingester first runs. A linked signal-cli device
receives no history from before it was linked.

## The daemon

Run signal-cli in multi-account mode with manual receiving, so that messages
wait on Signal's servers whenever the ingester is not subscribed:

```
signal-cli daemon --socket=/path/to/socket --receive-mode manual --no-receive-stdout
```

The daemon also accepts a socket passed by systemd socket activation
(`StandardInput=socket`). The socket is the only access control, so keep it in
a directory only the account owner can reach.

## Config

Config lives at `$XDG_CONFIG_HOME/signal-mcp/config.toml`, or at a path given
after the mode. Nothing is read from the environment, because MCP clients start
servers with little of it:

```toml
[signal]
database = "/home/me/.local/share/signal-mcp/messages.db"
socket = "/home/me/.local/state/signal-cli/socket"
# account = "+15555550100"  # required only when signal-cli holds several
```
