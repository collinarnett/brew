"""Grocy REST API client."""

import requests

from .models import GrocyProduct

REQUEST_TIMEOUT = 10


class GrocyClient:
    """Client for Grocy's REST API."""

    def __init__(self, base_url: str, api_key: str) -> None:
        """Initialize with Grocy instance URL and API key."""
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        self.session.headers.update(
            {
                "GROCY-API-KEY": api_key,
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )

    def get_products(self) -> list[GrocyProduct]:
        """Fetch all products from the Grocy inventory."""
        resp = self.session.get(
            f"{self.base_url}/api/objects/products",
            timeout=REQUEST_TIMEOUT,
        )
        resp.raise_for_status()
        return [GrocyProduct(id=p["id"], name=p["name"]) for p in resp.json()]

    def add_product_to_stock(
        self,
        product_id: int,
        amount: float,
        price: float | None = None,
    ) -> None:
        """Add stock to an existing product."""
        data: dict = {
            "amount": amount,
            "transaction_type": "purchase",
            "best_before_date": "2999-12-31",
        }
        if price is not None:
            data["price"] = price
        resp = self.session.post(
            f"{self.base_url}/api/stock/products/{product_id}/add",
            json=data,
            timeout=REQUEST_TIMEOUT,
        )
        resp.raise_for_status()
