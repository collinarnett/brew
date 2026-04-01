"""Import service — orchestrates Walmart and Grocy clients."""

import json
from pathlib import Path

from thefuzz import fuzz

from .grocy import GrocyClient
from .models import (
    GrocyProduct,
    ImportResult,
    ProductMatch,
    WalmartItem,
    WalmartOrder,
)
from .walmart import WalmartClient

FUZZY_MATCH_THRESHOLD = 75


def match_item(item: WalmartItem, products: list[GrocyProduct]) -> ProductMatch | None:
    """Fuzzy-match a Walmart item to a Grocy product."""
    best_match = None
    best_score = 0
    for product in products:
        score = fuzz.token_sort_ratio(item.name.lower(), product.name.lower())
        if score > best_score:
            best_score = score
            best_match = product
    if best_match and best_score >= FUZZY_MATCH_THRESHOLD:
        return ProductMatch(walmart_item=item, grocy_product=best_match, score=best_score)
    return None


def import_order(
    order: WalmartOrder,
    products: list[GrocyProduct],
    grocy: GrocyClient,
    *,
    dry_run: bool = False,
) -> ImportResult:
    """Match items from a Walmart order to Grocy products and add to stock."""
    matched = []
    unmatched = []
    for item in order.items:
        product_match = match_item(item, products)
        if product_match:
            matched.append(product_match)
            if not dry_run:
                grocy.add_product_to_stock(
                    product_match.grocy_product.id,
                    item.quantity,
                    price=item.line_price,
                )
        else:
            unmatched.append(item)
    return ImportResult(order_id=order.order_id, matched=matched, unmatched=unmatched)


class ImportState:
    """Tracks which orders have been imported."""

    def __init__(self, path: Path):
        self.path = path
        self._data = self._load()

    def _load(self) -> dict:
        if self.path.exists():
            return json.loads(self.path.read_text())
        return {"imported_orders": []}

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self._data, indent=2))

    def is_imported(self, order_id: str) -> bool:
        return order_id in self._data["imported_orders"]

    def mark_imported(self, order_id: str) -> None:
        self._data["imported_orders"].append(order_id)
        self.save()


def run_import(
    walmart: WalmartClient,
    grocy: GrocyClient,
    state: ImportState,
    *,
    since: int | None = None,
    limit: int = 10,
    dry_run: bool = False,
    force: bool = False,
) -> list[ImportResult]:
    """Fetch Walmart orders and import into Grocy."""
    products = grocy.get_products()
    summaries = walmart.get_purchase_history(limit=limit, min_timestamp=since)
    results = []
    seen_order_ids: set[str] = set()

    for summary in summaries:
        if summary.order_id in seen_order_ids:
            continue
        seen_order_ids.add(summary.order_id)

        if state.is_imported(summary.order_id) and not force:
            continue

        order = walmart.get_order(summary.order_id)
        result = import_order(order, products, grocy, dry_run=dry_run)
        results.append(result)

        if not dry_run:
            state.mark_imported(summary.order_id)

    return results
