"""Typed models for Walmart and Grocy data."""

from pydantic import BaseModel


class WalmartItem(BaseModel):
    name: str
    quantity: int
    line_price: float | None = None


class WalmartOrderSummary(BaseModel):
    order_id: str
    order_type: str
    item_count: int
    is_in_store: bool
    status: str
    items: list[WalmartItem]


class WalmartOrder(BaseModel):
    order_id: str
    items: list[WalmartItem]
    subtotal: float | None = None
    total: float | None = None


class GrocyProduct(BaseModel):
    id: int
    name: str


class ProductMatch(BaseModel):
    walmart_item: WalmartItem
    grocy_product: GrocyProduct
    score: int


class ImportResult(BaseModel):
    order_id: str
    matched: list[ProductMatch]
    unmatched: list[WalmartItem]
