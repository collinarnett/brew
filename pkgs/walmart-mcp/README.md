# walmart-mcp

MCP server exposing the `walmart` library. Runs over stdio by default,
or HTTP with `--http <port>`.

Tools:

- `walmart_search_products` — catalogue search by keyword, optionally
  restricted to a category. Returns name, brand, description, price in
  cents, price per unit, availability, and category path, alongside the
  categories Walmart offers to narrow the same search. Searching without
  a category is how a caller learns the id to pass back.
- `walmart_list_orders` — order summaries as JSON.
- `walmart_get_order` — full order detail with items and prices.
- `walmart_refresh_endpoints` — scan Walmart's current frontend build
  for persisted query hashes and update the catalog.

Every result is an object with a `notices` list, which is where the
server reports work it did on its own, such as refreshing the endpoint
catalog after Walmart retired a hash.

Authentication comes from the local Firefox session via
`browser-cookies`; the cookie database is read fresh on every call, so
re-logging into walmart.com takes effect immediately.

## Configuration

Reads `$XDG_CONFIG_HOME/walmart-mcp/config.toml` (or a path given as an
argument). Endpoint hashes are discovered at runtime, so the file
carries only the operations discovery cannot see:

```toml
# Optional; defaults to $XDG_STATE_HOME/walmart/catalog.json
catalog-file = "/home/you/.local/state/walmart/catalog.json"

[[operation]]
name = "getOrder"
hash = "..."
```

## Product detail and nutrition

Walmart serves item content — the long description, ingredient
statement, and nutrition panel — from its `pdp` gateway, which sits
behind PerimeterX and answers a request without a browser-minted `_px3`
token with HTTP 412 and a captcha challenge. Nothing here defeats that,
so those fields are not available and no tool claims to return them.
Search carries the item's short description, price, and category, which
is the detail this client can reach.
