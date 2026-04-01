"""Typed models for Walmart and Grocy data."""

from typing import Any

from pydantic import BaseModel, model_validator


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


# -- __NEXT_DATA__ parsing models --


class SSRProductInfo(BaseModel):
    name: str


class SSRLinePrice(BaseModel):
    value: float


class SSRPriceInfo(BaseModel):
    linePrice: SSRLinePrice | None = None


class SSROrderItem(BaseModel):
    quantity: int
    productInfo: SSRProductInfo
    priceInfo: SSRPriceInfo | None = None


class SSROrderGroup(BaseModel):
    items: list[SSROrderItem]


class SSRPriceLineItem(BaseModel):
    value: float


class SSRPriceDetails(BaseModel):
    subTotal: SSRPriceLineItem | None = None
    grandTotal: SSRPriceLineItem | None = None


class SSROrder(BaseModel):
    """Order data from __NEXT_DATA__.props.pageProps.initialData.data.order.

    The groups key is a GraphQL alias that changes with schema versions
    (e.g. groups_2101). We find it dynamically: the first list-valued key
    whose elements contain an 'items' key.
    """

    id: str
    priceDetails: SSRPriceDetails | None = None
    groups: list[SSROrderGroup]

    @model_validator(mode="before")
    @classmethod
    def find_groups_key(cls, data: Any) -> Any:
        if isinstance(data, dict) and "groups" not in data:
            for key, value in data.items():
                if (
                    isinstance(value, list)
                    and value
                    and isinstance(value[0], dict)
                    and "items" in value[0]
                ):
                    data["groups"] = value
                    break
        return data

    def to_walmart_order(self) -> WalmartOrder:
        items = []
        for group in self.groups:
            for item in group.items:
                items.append(
                    WalmartItem(
                        name=item.productInfo.name,
                        quantity=item.quantity,
                        line_price=item.priceInfo.linePrice.value
                        if item.priceInfo and item.priceInfo.linePrice
                        else None,
                    )
                )
        return WalmartOrder(
            order_id=self.id,
            items=items,
            subtotal=self.priceDetails.subTotal.value
            if self.priceDetails and self.priceDetails.subTotal
            else None,
            total=self.priceDetails.grandTotal.value
            if self.priceDetails and self.priceDetails.grandTotal
            else None,
        )


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
