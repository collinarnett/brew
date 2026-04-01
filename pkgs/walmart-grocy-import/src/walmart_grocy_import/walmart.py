"""Walmart API clients.

WalmartGraphQLClient — order listing via PurchaseHistoryV2.
WalmartPageScraper — order details with per-item prices from SSR __NEXT_DATA__.
"""

import json
import re
import time

import requests

from .browser import LightpandaBrowser
from .config import REQUEST_TIMEOUT, WALMART_BASE
from .models import (
    GQLDataEnvelope,
    NextDataEnvelope,
    WalmartOrder,
    WalmartOrderSummary,
)

BASE_HEADERS: dict[str, str] = {
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
HTTP_RATE_LIMITED = 429
HTTP_FORBIDDEN = 403
HTTP_TEAPOT = 418
NEXT_DATA_PATTERN = re.compile(
    r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
)


class WalmartGraphQLClient:
    """Client for Walmart's consumer GraphQL API (order listing)."""

    def __init__(
        self,
        session: requests.Session,
        endpoints: dict[str, str],
    ) -> None:
        """Initialize with an authenticated session and endpoints."""
        self._session = session
        self._endpoints = endpoints
        self._last_request: float = 0

    def _rate_limit(self) -> None:
        elapsed = time.monotonic() - self._last_request
        if self._last_request > 0 and elapsed < RATE_LIMIT_SECONDS:
            time.sleep(RATE_LIMIT_SECONDS - elapsed)
        self._last_request = time.monotonic()

    def _request(
        self,
        url: str,
        operation_name: str,
        variables: dict,
    ) -> dict:
        self._rate_limit()
        correlation_id = f"wgi-{int(time.time())}"
        self._session.headers.update(
            {
                "x-apollo-operation-name": operation_name,
                "x-o-gql-query": f"query {operation_name}",
                "x-o-correlation-id": correlation_id,
                "wm_qos.correlation_id": correlation_id,
            },
        )
        resp = self._session.get(
            url,
            params={"variables": json.dumps(variables)},
            timeout=REQUEST_TIMEOUT,
        )

        if resp.status_code == HTTP_RATE_LIMITED:
            msg = "Rate limited — log into walmart.com again"
            raise RuntimeError(msg)
        if resp.status_code in (HTTP_FORBIDDEN, HTTP_TEAPOT):
            msg = "Access denied — cookies expired, log into walmart.com"
            raise RuntimeError(msg)
        resp.raise_for_status()
        return resp.json()

    def get_purchase_history(
        self,
        *,
        limit: int = 20,
        min_timestamp: int | None = None,
        max_timestamp: int | None = None,
    ) -> list[WalmartOrderSummary]:
        """Fetch recent order summaries from Walmart."""
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
        raw = self._request(
            self._endpoints["PurchaseHistoryV2"],
            "PurchaseHistoryV2",
            variables,
        )
        envelope = GQLDataEnvelope.model_validate(raw)
        return [
            g.to_summary()
            for g in envelope.data.order_history_v2.order_groups
        ]


class WalmartPageScraper:
    """Extracts order details with prices from Walmart's SSR pages."""

    def __init__(self, browser: LightpandaBrowser) -> None:
        """Initialize with a running LightpandaBrowser instance."""
        self._browser = browser

    def get_order(self, order_id: str) -> WalmartOrder:
        """Fetch order details by rendering the authenticated order page."""
        html = self._browser.render(
            f"{WALMART_BASE}/orders/{order_id}",
        )

        match = NEXT_DATA_PATTERN.search(html)
        if not match:
            msg = f"No __NEXT_DATA__ found for order {order_id}"
            raise RuntimeError(msg)

        envelope = NextDataEnvelope.model_validate(
            json.loads(match.group(1)),
        )
        return (
            envelope.props.page_props.initial_data.data.order
            .to_walmart_order()
        )
