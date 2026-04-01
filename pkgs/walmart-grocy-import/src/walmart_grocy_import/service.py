"""Import service — orchestrates Walmart and Grocy clients."""

import json
from pathlib import Path

import browser_cookie3
import requests
from thefuzz import fuzz

from .browser import LightpandaBrowser
from .extractor import resolve_endpoints
from .grocy import GrocyClient
from .models import (
    GrocyProduct,
    ImportResult,
    ProductMatch,
    WalmartItem,
    WalmartOrder,
)
from .walmart import BASE_HEADERS, WalmartGraphQLClient, WalmartPageScraper

FUZZY_MATCH_THRESHOLD = 75


def get_walmart_cookies() -> tuple[requests.cookies.RequestsCookieJar, list[dict]]:
    """Extract Walmart cookies from Firefox, returning both requests and Playwright formats."""
    cookies = browser_cookie3.firefox(domain_name=".walmart.com")

    pw_cookies = []
    for c in cookies:
        cookie: dict = {
            "name": c.name,
            "value": c.value,
            "domain": c.domain,
            "path": c.path or "/",
            "secure": bool(c.secure),
            "httpOnly": False,
        }
        if c.expires and 0 < c.expires < 2**31:
            cookie["expires"] = int(c.expires)
        pw_cookies.append(cookie)

    return cookies, pw_cookies


def make_session(cookies: requests.cookies.RequestsCookieJar) -> requests.Session:
    session = requests.Session()
    session.cookies = cookies
    session.headers.update(BASE_HEADERS)
    return session


def match_item(item: WalmartItem, products: list[GrocyProduct]) -> ProductMatch | None:
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
    grocy: GrocyClient,
    state: ImportState,
    req_cookies: requests.cookies.RequestsCookieJar,
    pw_cookies: list[dict],
    *,
    since: int | None = None,
    limit: int = 10,
    dry_run: bool = False,
    force: bool = False,
) -> list[ImportResult]:
    products = grocy.get_products()

    with LightpandaBrowser(pw_cookies) as browser:
        endpoints = resolve_endpoints(browser)
        graphql = WalmartGraphQLClient(make_session(req_cookies), endpoints)
        scraper = WalmartPageScraper(browser)

        summaries = graphql.get_purchase_history(limit=limit, min_timestamp=since)
        results = []
        seen: set[str] = set()

        for summary in summaries:
            if summary.order_id in seen:
                continue
            seen.add(summary.order_id)

            if state.is_imported(summary.order_id) and not force:
                continue

            order = scraper.get_order(summary.order_id)
            result = import_order(order, products, grocy, dry_run=dry_run)
            results.append(result)

            if not dry_run:
                state.mark_imported(summary.order_id)

    return results


def run_list(
    req_cookies: requests.cookies.RequestsCookieJar,
    pw_cookies: list[dict],
    *,
    since: int | None = None,
    limit: int = 10,
) -> list:
    with LightpandaBrowser(pw_cookies) as browser:
        endpoints = resolve_endpoints(browser)
        graphql = WalmartGraphQLClient(make_session(req_cookies), endpoints)
        return graphql.get_purchase_history(limit=limit, min_timestamp=since)
