# walmart-mcp

MCP server exposing the `walmart` library. Runs over stdio by default,
or HTTP with `--http <port>`.

Tools:

- `walmart_list_orders` — order summaries as JSON (`since`, `limit`).
- `walmart_get_order` — full order detail with items and prices
  (`order_id`, `channel`).

Authentication comes from the local Firefox session via
`browser-cookies`; the cookie database is read fresh on every call, so
re-logging into walmart.com takes effect immediately.
