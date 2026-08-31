# Inventory and ordering through the tools

This applies when the `grocy`, `walmart`, and `nutrition` MCP servers are
connected. Without them, the skill runs the manual way: ask what they
have, and leave the shopping to them. Never invent stock, prices, or
availability that a tool could have reported.

Three servers, three jobs. Grocy holds what is in the house and what was
cooked. Walmart is where the food comes from. Nutrition turns a package
barcode into a label. The skill decides; the servers only answer.

## Contents
- [Before designing: what they already have](#before-designing-what-they-already-have)
- [Pricing and availability while reconciling](#pricing-and-availability-while-reconciling)
- [Nutrition from the package, not from memory](#nutrition-from-the-package-not-from-memory)
- [Ordering, after the plan is confirmed](#ordering-after-the-plan-is-confirmed)
- [When the order arrives](#when-the-order-arrives)
- [When prep is done](#when-prep-is-done)
- [Things that go wrong](#things-that-go-wrong)

---

## Before designing: what they already have

Call `grocy_get_stock` first. Everything it returns is the "already
have" bucket, with amounts in the product's stock unit and a next due
date. Use it in two ways:

- **Design toward it.** A half bag of frozen cauliflower, the other half
  of the pepper strips, an open jar of gochujang: these are free
  ingredients and they decide which recipes cost the least.
- **Prefer recipes Grocy already holds.** `grocy_list_recipes` names
  them; `grocy_recipe_fulfillment` says whether stock covers one and how
  many products are missing. A recipe that is nearly covered is a
  strong candidate for the week. Its userfields
  (`grocy_get_userfields entity=recipes`) carry the verified macros from
  when it was first built, so it does not need re-verifying.

Products Grocy knows but has no stock of still matter: their userfields
hold nutrition per serving, and their barcodes are how a Walmart item is
recognised next time.

## Pricing and availability while reconciling

Step 6 of the skill reconciles the list. With the tools, reconcile
against the store, not against memory:

1. `walmart_get_cart` once, to learn the cart id and the store the
   session is assorted against. Stock answers are about that store.
2. For each buy line, `walmart_search_products` with the ingredient as
   the query and the Food department as `category_id` (the first search
   returns the department ids; `976759` has been Food). Take the first
   in-stock result whose form matches the recipe (pre-cut, frozen,
   canned, as the skill prefers). Record its `us_item_id`, `offer_id`,
   price, and unit price. Budget is the sum of those prices, not a
   guess.
3. For lines that are out of stock or absent, `walmart_find_stores`
   around their postal code, then `walmart_compare_stores` with the
   nearby store ids and the missing queries. Pick the store with the
   largest in-stock count; report the distance and what it still lacks.
   If a different store wins, say so plainly before the plan is
   confirmed, because the delivery fee and slots change with it. The
   comparison puts the cart back on the original store by itself and
   reports `restored`; if that is false, tell them which store the
   session is on now.
4. For any item that will be stocked in Grocy by weight or volume,
   `walmart_get_product` gives the package's `net_content`. That is the
   purchase unit: "1 lb", "12 oz", "1 GAL". The shopping list states
   package counts, and the recipe arithmetic uses net content, never the
   listing title.

Keep the searches few. The site's bot protection trips on bursts and
then refuses every tool for half an hour; the servers space their own
requests, but a plan with forty ingredients still means forty searches.
Search once per ingredient, not once per candidate.

## Nutrition from the package, not from memory

For a branded item, the label is reachable deterministically:

1. `walmart_get_product` returns the package `upc`.
2. `nutrition_by_barcode` with that UPC returns the label per serving
   and per 100 g, the serving size, and the ingredient statement.

That replaces the web search for branded products. Mark the figure as
"label" in the plan's numbers. When `found` is false, fall back to the
search patterns in `verification.md` and mark the figure as an estimate.
Produce and meat sold loose have no UPC, so those stay on the USDA
reference values.

Save what was found so it is never looked up twice: when the Grocy
product is created, `grocy_set_userfields entity=products` with the
per-serving values and `source` set to the barcode and database. A
product seen again next week is exact.

## Ordering, after the plan is confirmed

Nothing below runs until the person has confirmed the plan. Each call
changes their real Walmart account.

1. `walmart_update_cart` once per buy line with the `offer_id` and the
   package count. Read the receipt: the subtotal and any line Walmart
   refused.
2. `walmart_get_cart` to show the priced cart: subtotal, the order
   minimum, the below-minimum fee if it applies, and the estimated total.
   Compare to the budget here, not after the slot is booked.
3. `walmart_list_slots` and present the days and windows with fees.
   Express slots (a promise in minutes) cost money; scheduled windows
   are free for the member tier. Let them choose.
4. `walmart_reserve_slot` with the chosen slot's `slot_metadata`, taken
   verbatim from the listing. Report `held_until`: the reservation lasts
   about twenty minutes, and the order has to be placed in the browser
   before then. Checkout and payment are theirs to do, never the tool's.

Changing the cart after reserving is fine; changing the store drops the
reservation.

## When the order arrives

The person says the order is in. Then:

1. `walmart_list_orders` and `walmart_get_order` for the delivered order:
   real quantities (weight items arrive as a decimal) and real prices.
2. For each line, `grocy_find_product_by_barcode` with the item's UPC
   from `walmart_get_product`. Known product: stock it. Unknown:
   - `grocy_ensure_location` for where it lives, `grocy_ensure_shopping_location`
     for Walmart, `grocy_find_quantity_unit` for the stock unit the
     recipes will consume in (oz, lb, fl oz, each).
   - `grocy_create_product`, then `grocy_add_product_barcode` with the
     UPC and a note naming the Walmart item id.
   - If the purchase unit differs from the recipe unit,
     `grocy_add_unit_conversion` for that product (1 lb = 16 oz).
   - `grocy_set_userfields` with the nutrition found earlier.
3. `grocy_add_stock` with the amount in the stock unit, the price in
   cents from the order line, the delivery date, the Walmart shopping
   location, and the order id as the note. Best-before comes from the
   product page's shelf-life row when it has one; otherwise leave it
   unset.
4. Create each recipe of the plan: `grocy_create_recipe` with the
   household servings, `grocy_add_recipe_ingredient` per line in the
   recipe's unit, and `grocy_set_userfields entity=recipes` with the
   per-serving numbers and their basis. `grocy_recipe_fulfillment` should
   now report every recipe fulfilled; if one is not, a quantity or a
   unit conversion is wrong, and this is the moment to find it.

## When prep is done

`grocy_consume_recipe` per recipe cooked. Grocy removes every ingredient
in one booking through the unit conversions. Something cooked off-plan
is `grocy_consume_product`. Then `grocy_get_stock` once more and tell
them what is left: that is next week's "already have" list.

## Things that go wrong

- A tool says the cart is on a store they did not choose. Walmart infers
  the store from the browser session; `walmart_set_store` fixes it and
  every stock answer after that is about the right place.
- `walmart_search_products` returns nothing in stock for a staple.
  Search again with a broader term before declaring it unavailable; the
  catalogue names things oddly. Then compare stores.
- The reservation expired. List slots again and reserve again; the cart
  is unchanged.
- `nutrition_by_barcode` finds the code but the serving is in a unit the
  recipe does not use (240 ml of milk, 112 g of beef). Convert with the
  per-100 g figures and the package net content; say which basis was
  used.
- Grocy refuses a consume because stock is short. Quantities were wrong
  at arrival, or someone ate it. Ask, then `grocy_consume_product` for
  what was actually used.
