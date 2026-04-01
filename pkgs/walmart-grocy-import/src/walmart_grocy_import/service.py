"""Import service — orchestrates Walmart and Grocy clients."""

import json
from pathlib import Path

import browser_cookie3
import requests
from requests.cookies import RequestsCookieJar
from thefuzz import fuzz

from .browser import LightpandaBrowser
from .config import ImportOptions
from .extractor import resolve_endpoints
from .grocy import GrocyClient
from .models import (
    GrocyProduct,
    ImportResult,
    ProductMatch,
    WalmartItem,
    WalmartOrder,
    WalmartOrderSummary,
)
from .walmart import BASE_HEADERS, WalmartGraphQLClient, WalmartPageScraper

FUZZY_MATCH_THRESHOLD = 75

WalmartCookies = tuple[RequestsCookieJar, list[dict[str, object]]]


def get_walmart_cookies() -> WalmartCookies:
    """Extract Walmart cookies from Firefox.

    Returns both requests and Playwright cookie formats.
    """
    jar = browser_cookie3.firefox(domain_name=".walmart.com")
    cookies = RequestsCookieJar()
    cookies.update(jar)

    pw_cookies = []
    for c in jar:
        cookie: dict = {
            "name": c.name,
            "value": c.value,
            "domain": c.domain,
            "path": c.path or "/",
            "secure": bool(c.secure),
            "httpOnly": False,
        }
        max_expires = 2**31
        if c.expires and 0 < c.expires < max_expires:
            cookie["expires"] = int(c.expires)
        pw_cookies.append(cookie)

    return cookies, pw_cookies


def make_session(
    cookies: RequestsCookieJar,
) -> requests.Session:
    """Create a requests session with Walmart headers and cookies."""
    session = requests.Session()
    session.cookies = cookies
    session.headers.update(BASE_HEADERS)
    return session


def match_item(
    item: WalmartItem,
    products: list[GrocyProduct],
) -> ProductMatch | None:
    """Fuzzy-match a Walmart item to a Grocy product."""
    best_match = None
    best_score = 0
    for product in products:
        score = fuzz.token_sort_ratio(
            item.name.lower(),
            product.name.lower(),
        )
        if score > best_score:
            best_score = score
            best_match = product
    if best_match and best_score >= FUZZY_MATCH_THRESHOLD:
        return ProductMatch(
            walmart_item=item,
            grocy_product=best_match,
            score=best_score,
        )
    return None


def import_order(
    order: WalmartOrder,
    products: list[GrocyProduct],
    grocy: GrocyClient,
    *,
    dry_run: bool = False,
) -> ImportResult:
    """Match items from a Walmart order and add matched items to Grocy stock."""
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
    return ImportResult(
        order_id=order.order_id,
        matched=matched,
        unmatched=unmatched,
    )


class ImportState:
    """Tracks which orders have been imported to avoid duplicates."""

    def __init__(self, path: Path) -> None:
        """Initialize with path to the state file."""
        self.path = path
        self._data = self._load()

    def _load(self) -> dict:
        if self.path.exists():
            return json.loads(self.path.read_text())
        return {"imported_orders": []}

    def save(self) -> None:
        """Persist imported order IDs to disk."""
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self._data, indent=2))

    def is_imported(self, order_id: str) -> bool:
        """Check if an order has already been imported."""
        return order_id in self._data["imported_orders"]

    def mark_imported(self, order_id: str) -> None:
        """Record an order as imported."""
        self._data["imported_orders"].append(order_id)
        self.save()


def _deduplicate(
    summaries: list[WalmartOrderSummary],
) -> list[WalmartOrderSummary]:
    """Remove duplicate order IDs (Walmart returns one group per fulfillment)."""
    seen: set[str] = set()
    result = []
    for s in summaries:
        if s.order_id not in seen:
            seen.add(s.order_id)
            result.append(s)
    return result


def run_import(
    grocy: GrocyClient,
    state: ImportState,
    cookies: WalmartCookies,
    options: ImportOptions,
) -> list[ImportResult]:
    """Fetch Walmart orders and import into Grocy."""
    req_cookies, pw_cookies = cookies
    products = grocy.get_products()

    with LightpandaBrowser(pw_cookies) as browser:
        endpoints = resolve_endpoints(browser)
        graphql = WalmartGraphQLClient(make_session(req_cookies), endpoints)
        scraper = WalmartPageScraper(browser)

        summaries = _deduplicate(
            graphql.get_purchase_history(
                limit=options.limit,
                min_timestamp=options.since,
            ),
        )
        results = []

        for summary in summaries:
            if state.is_imported(summary.order_id) and not options.force:
                continue

            order = scraper.get_order(summary.order_id)
            result = import_order(
                order,
                products,
                grocy,
                dry_run=options.dry_run,
            )
            results.append(result)

            if not options.dry_run:
                state.mark_imported(summary.order_id)

    return results


def run_list(
    cookies: WalmartCookies,
    *,
    since: int | None = None,
    limit: int = 10,
) -> list[WalmartOrderSummary]:
    """List recent Walmart orders."""
    req_cookies, pw_cookies = cookies
    with LightpandaBrowser(pw_cookies) as browser:
        endpoints = resolve_endpoints(browser)
        graphql = WalmartGraphQLClient(make_session(req_cookies), endpoints)
        return graphql.get_purchase_history(limit=limit, min_timestamp=since)
