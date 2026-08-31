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
- `grocy_ensure_quantity_unit` — the id of a unit, creating it if missing.
- `grocy_get_stock`, `grocy_get_product_details`, `grocy_search_products`,
  `grocy_consume_product` — stock position and consumption.
- `grocy_add_product_barcode`, `grocy_find_product_by_barcode` — link a
  package UPC to a product and find it again.
- `grocy_add_unit_conversion` — declare e.g. 1 lb = 16 oz for a product.
- `grocy_create_recipe`, `grocy_list_recipes`, `grocy_update_recipe`, `grocy_add_recipe_ingredient`,
  `grocy_get_recipe_ingredients`, `grocy_recipe_fulfillment`,
  `grocy_consume_recipe` — recipes and consuming them from stock.
- `grocy_set_userfields`, `grocy_get_userfields` — custom text fields on
  products and recipes, declared on first use.
- `grocy_delete_recipe` joins the delete tools.
- `grocy_delete_product` / `grocy_delete_location` /
  `grocy_delete_shopping_location` / `grocy_delete_quantity_unit` —
  permanently remove one object.

## Configuration

Reads `$XDG_CONFIG_HOME/grocy-mcp/config.toml` (or a path given as the
first argument). The API key is referenced as a path to a file holding
the secret, never written inline:

```toml
[grocy]
url = "https://grocy.example.com"
api-key-file = "/path/to/grocy-api-key"
```
