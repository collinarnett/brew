# grocy-mcp

MCP server exposing the `grocy` library. Runs over stdio by default,
or HTTP with `--http <port>`.

Tools:

- `grocy_get_products` — all products as JSON.
- `grocy_create_product` — create a product from a name and object ids.
- `grocy_add_stock` — record a purchase (amount, optional price in
  cents, purchase date, optional best-before).
- `grocy_ensure_location` / `grocy_ensure_shopping_location` — resolve
  a name to an id, creating the object if missing.
- `grocy_find_quantity_unit` — resolve a name to an id; must exist.

## Configuration

Reads `$XDG_CONFIG_HOME/grocy-mcp/config.toml` (or a path given as the
first argument). The API key is referenced as a path to a file holding
the secret, never written inline:

```toml
[grocy]
url = "https://grocy.example.com"
api-key-file = "/path/to/grocy-api-key"
```
