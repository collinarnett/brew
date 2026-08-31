# nutrition-mcp

MCP server over the `openfoodfacts` library.

- `nutrition_by_barcode` — the label for a package barcode: per 100 g and
  per serving, serving size, ingredients. Unknown barcodes answer
  `found: false`.

Config at `$XDG_CONFIG_HOME/nutrition-mcp/config.toml`:

```toml
[openfoodfacts]
user-agent = "nutrition-mcp/0.1 (https://example.org/contact)"
```
