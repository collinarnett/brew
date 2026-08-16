# walmart-grocy-import

CLI tool that imports Walmart order history into [Grocy](https://grocy.info) inventory.

## Configuration

The `import` command reads `$XDG_CONFIG_HOME/walmart-grocy-import/config.toml`
(override with `--config FILE`). The API key is referenced as a path to a file
holding the secret, never written inline:

```toml
[grocy]
url = "https://grocy.example.com"
api-key-file = "/path/to/grocy-api-key"

[import]
location = "Pantry"
shopping-location = "Walmart"
quantity-unit = "Piece"
```

## Usage

List recent orders:

```
walmart-grocy-import list --since "7 days ago" --limit 10
```

Import into Grocy:

```
walmart-grocy-import import --since "30 days ago" --limit 20
```

Preview what would be imported without modifying Grocy:

```
walmart-grocy-import import --dry-run --since "7 days ago"
```

## How it works

For each Walmart order, the tool fetches the full item list with per-item prices, then reconciles each item against existing Grocy products using fuzzy name matching (threshold: 75/100). Items that match an existing product get stocked directly. Unmatched items create a new Grocy product and then stock it.

On the first real (non-dry-run) import, the tool creates the configured location and shopping location in Grocy if they don't exist. The quantity unit must already exist.

## State tracking

Imported order IDs are saved to `~/.local/share/walmart-grocy-import/state.json`. Subsequent runs skip already-imported orders. Use `--force` to re-import them.

If an order fails partway through, any order that stocked at least one item is also recorded, so a retry cannot stock those items twice; the items that were not imported are listed in the failure output for manual follow-up. A run with execution failures exits non-zero.

## Dependencies

Composes three libraries:
- `browser-cookies` — extracts Walmart session cookies from Firefox
- `walmart` — fetches order history and item details from Walmart's GraphQL API
- `grocy` — hand-written client for Grocy's REST API

## Options

| Flag | Description |
|------|-------------|
| `--since TEXT` | Time filter, e.g. `"7 days ago"`, `"2 weeks ago"` |
| `--limit INT` | Maximum orders to fetch (default: 10) |
| `--dry-run` | Show what would be imported without modifying Grocy |
| `--force` | Re-import orders that were already imported |
| `--config FILE` | Config file path (import only) |
