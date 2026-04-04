# walmart-grocy-import

CLI tool that imports Walmart order history into [Grocy](https://grocy.info) inventory.

## Usage

List recent orders:

```
walmart-grocy-import list --since "7 days ago" --limit 10
```

Import into Grocy:

```
walmart-grocy-import import --since "30 days ago" --limit 20 \
  --grocy-url https://grocy.example.com \
  --grocy-api-key your-key
```

Preview what would be imported without modifying Grocy:

```
walmart-grocy-import import --dry-run --since "7 days ago" \
  --grocy-url https://grocy.example.com \
  --grocy-api-key your-key
```

## How it works

For each Walmart order, the tool fetches the full item list with per-item prices, then reconciles each item against existing Grocy products using fuzzy name matching (threshold: 75/100). Items that match an existing product get stocked directly. Unmatched items create a new Grocy product and then stock it.

On first run, the tool creates the required Grocy entities (a "Pantry" location, a "Walmart" shopping location, and a "Piece" quantity unit) if they don't exist.

## State tracking

Imported order IDs are saved to `~/.local/share/walmart-grocy-import/state.json`. Subsequent runs skip already-imported orders. Use `--force` to re-import them.

## Dependencies

Composes three libraries:
- `browser-cookies` — extracts Walmart session cookies from Firefox
- `walmart` — fetches order history and item details from Walmart's GraphQL API
- `grocy-client` — generated client for Grocy's REST API

## Options

| Flag | Description |
|------|-------------|
| `--since TEXT` | Time filter, e.g. `"7 days ago"`, `"2 weeks ago"` |
| `--limit INT` | Maximum orders to fetch (default: 10) |
| `--dry-run` | Show what would be imported without modifying Grocy |
| `--force` | Re-import orders that were already imported |
| `--grocy-url TEXT` | Grocy instance URL |
| `--grocy-api-key TEXT` | Grocy API key |
| `-v, --verbose` | Log HTTP requests to stderr |
