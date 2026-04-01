"""Walmart consumer API client.

Uses GraphQL for order listing (PurchaseHistoryV2) and Lightpanda CDP
for order details with per-item prices (parsed from SSR __NEXT_DATA__).
"""

import json
import re
import subprocess
import time

import browser_cookie3
import requests
from playwright.sync_api import sync_playwright

from .extractor import resolve_endpoints
from .models import WalmartItem, WalmartOrder, WalmartOrderSummary

WALMART_BASE = "https://www.walmart.com"

BASE_HEADERS = {
    "accept": "application/json",
    "accept-language": "en-US",
    "content-type": "application/json",
    "user-agent": (
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    ),
    "x-o-platform": "rweb",
    "x-o-bu": "WALMART-US",
    "x-o-mart": "B2C",
    "x-o-segment": "oaoh",
    "wm_mp": "true",
    "sec-fetch-site": "same-origin",
    "sec-fetch-mode": "cors",
    "sec-fetch-dest": "empty",
    "dnt": "1",
    "x-o-platform-version": "usweb-1.221.0",
    "x-enable-server-timing": "1",
    "x-latency-trace": "1",
}

RATE_LIMIT_SECONDS = 2
NEXT_DATA_PATTERN = re.compile(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>')


def get_cookies() -> requests.cookies.RequestsCookieJar:
    """Extract Walmart cookies from Firefox's cookie store."""
    return browser_cookie3.firefox(domain_name=".walmart.com")


def _cookies_for_playwright(cookies) -> list[dict]:
    pw_cookies = []
    for c in cookies:
        cookie = {
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
    return pw_cookies


def _parse_order_summary(raw: dict) -> WalmartOrderSummary:
    status_parts = []
    if raw.get("status") and raw["status"].get("message"):
        status_parts = [p["text"] for p in raw["status"]["message"]["parts"]]

    return WalmartOrderSummary(
        order_id=raw["orderId"],
        order_type=raw.get("derivedFulfillmentType", raw["type"]),
        item_count=raw["itemCount"],
        is_in_store=raw["type"] == "IN_STORE",
        status=" ".join(status_parts).strip(),
        items=[
            WalmartItem(name=item["name"], quantity=item["quantity"])
            for item in raw["items"]
        ],
    )


def _parse_next_data_order(next_data: dict) -> WalmartOrder:
    """Extract order details with per-item prices from __NEXT_DATA__ SSR payload."""
    props = next_data["props"]["pageProps"]["initialData"]["data"]["order"]

    items = []
    for key, value in props.items():
        if not isinstance(value, list):
            continue
        for group in value:
            if not isinstance(group, dict):
                continue
            for item in group.get("items", []):
                product_info = item.get("productInfo", {})
                price_info = item.get("priceInfo", {})
                line_price_raw = price_info.get("linePrice")
                name = product_info.get("name") or item.get("name")
                if not name:
                    continue
                items.append(
                    WalmartItem(
                        name=name,
                        quantity=int(item.get("quantity", 1)),
                        line_price=line_price_raw["value"] if line_price_raw else None,
                    )
                )

    price_details = props.get("priceDetails", {})
    subtotal_raw = price_details.get("subTotal")
    total_raw = price_details.get("grandTotal")

    return WalmartOrder(
        order_id=props.get("id", ""),
        items=items,
        subtotal=subtotal_raw["value"] if subtotal_raw else None,
        total=total_raw["value"] if total_raw else None,
    )


def _fetch_order_page(order_id: str, pw_cookies: list[dict]) -> str:
    """Render an authenticated order detail page via Lightpanda CDP."""
    proc = subprocess.Popen(
        ["lightpanda", "serve", "--host", "127.0.0.1", "--port", "9222"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    time.sleep(2)

    try:
        with sync_playwright() as p:
            browser = p.chromium.connect_over_cdp("ws://127.0.0.1:9222")
            context = browser.new_context()
            context.add_cookies(pw_cookies)
            page = context.new_page()
            page.goto(
                f"{WALMART_BASE}/orders/{order_id}",
                wait_until="networkidle",
                timeout=30000,
            )
            html = page.content()
            browser.close()
    finally:
        proc.terminate()
        proc.wait()

    return html


class WalmartClient:
    """Client for Walmart's consumer API."""

    def __init__(self, cookie_jar: requests.cookies.RequestsCookieJar, endpoints: dict[str, str]):
        self.session = requests.Session()
        self.session.cookies = cookie_jar
        self.session.headers.update(BASE_HEADERS)
        self._last_request: float = 0
        self._endpoints = endpoints
        self._pw_cookies = _cookies_for_playwright(cookie_jar)

    def _rate_limit(self) -> None:
        elapsed = time.monotonic() - self._last_request
        if self._last_request > 0 and elapsed < RATE_LIMIT_SECONDS:
            time.sleep(RATE_LIMIT_SECONDS - elapsed)
        self._last_request = time.monotonic()

    def _graphql(self, url: str, operation_name: str, variables: dict) -> dict:
        self._rate_limit()
        self.session.headers.update(
            {
                "x-apollo-operation-name": operation_name,
                "x-o-gql-query": f"query {operation_name}",
                "x-o-correlation-id": f"wgi-{int(time.time())}",
                "wm_qos.correlation_id": f"wgi-{int(time.time())}",
            }
        )
        resp = self.session.get(url, params={"variables": json.dumps(variables)}, timeout=15)

        if resp.status_code == 429:
            raise RuntimeError("Rate limited — cookies may be stale, log into walmart.com again")
        if resp.status_code in (403, 418):
            raise RuntimeError("Access denied — cookies expired, log into walmart.com in Firefox")
        resp.raise_for_status()
        return resp.json()

    def get_purchase_history(
        self,
        *,
        limit: int = 20,
        min_timestamp: int | None = None,
        max_timestamp: int | None = None,
    ) -> list[WalmartOrderSummary]:
        variables = {
            "input": {
                "cursor": "",
                "search": "",
                "filterIds": [],
                "limit": limit,
                "type": None,
                "minTimestamp": min_timestamp,
                "maxTimestamp": max_timestamp,
            },
            "platform": "WEB",
        }
        data = self._graphql(
            self._endpoints["PurchaseHistoryV2"], "PurchaseHistoryV2", variables
        )
        return [
            _parse_order_summary(o)
            for o in data["data"]["orderHistoryV2"]["orderGroups"]
        ]

    def get_order(self, order_id: str) -> WalmartOrder:
        """Fetch order details with per-item prices via Lightpanda CDP."""
        html = _fetch_order_page(order_id, self._pw_cookies)

        match = NEXT_DATA_PATTERN.search(html)
        if not match:
            raise RuntimeError(f"No __NEXT_DATA__ found for order {order_id}")

        return _parse_next_data_order(json.loads(match.group(1)))
