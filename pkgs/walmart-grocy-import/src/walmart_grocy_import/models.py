"""Typed models for Walmart and Grocy data."""

from typing import Any

from pydantic import BaseModel, ConfigDict, Field, model_validator


class WalmartItem(BaseModel):
    """A grocery item from a Walmart order."""

    name: str
    quantity: int
    line_price: float | None = None


class WalmartOrderSummary(BaseModel):
    """Summary of a Walmart order from the purchase history listing."""

    order_id: str
    order_type: str
    item_count: int
    is_in_store: bool
    status: str
    items: list[WalmartItem]


class WalmartOrder(BaseModel):
    """Full Walmart order with per-item prices."""

    order_id: str
    items: list[WalmartItem]
    subtotal: float | None = None
    total: float | None = None


# -- __NEXT_DATA__ parsing models --
# Field names match Walmart's JSON keys via aliases.


class SSRProductInfo(BaseModel):
    """Product name from Walmart's SSR payload."""

    name: str


class SSRLinePrice(BaseModel):
    """A price value from Walmart's SSR payload."""

    value: float


class SSRPriceInfo(BaseModel):
    """Price info for a single item in Walmart's SSR payload."""

    model_config = ConfigDict(populate_by_name=True)

    line_price: SSRLinePrice | None = Field(default=None, alias="linePrice")


class SSROrderItem(BaseModel):
    """A single item in an order group from Walmart's SSR payload."""

    model_config = ConfigDict(populate_by_name=True)

    quantity: int
    product_info: SSRProductInfo = Field(alias="productInfo")
    price_info: SSRPriceInfo | None = Field(default=None, alias="priceInfo")


class SSROrderGroup(BaseModel):
    """A fulfillment group containing items from Walmart's SSR payload."""

    items: list[SSROrderItem]


class SSRPriceLineItem(BaseModel):
    """A labeled price value from Walmart's SSR payload."""

    value: float


class SSRPriceDetails(BaseModel):
    """Order-level pricing from Walmart's SSR payload."""

    model_config = ConfigDict(populate_by_name=True)

    sub_total: SSRPriceLineItem | None = Field(default=None, alias="subTotal")
    grand_total: SSRPriceLineItem | None = Field(default=None, alias="grandTotal")


class SSROrder(BaseModel):
    """Order data from __NEXT_DATA__.props.pageProps.initialData.data.order.

    The groups key is a GraphQL alias that changes with schema versions
    (e.g. groups_2101). We find it dynamically: the first list-valued key
    whose elements contain an 'items' key.
    """

    model_config = ConfigDict(populate_by_name=True)

    id: str
    price_details: SSRPriceDetails | None = Field(default=None, alias="priceDetails")
    groups: list[SSROrderGroup]

    @model_validator(mode="before")
    @classmethod
    def find_groups_key(cls, data: dict[str, Any]) -> dict[str, Any]:
        """Locate the aliased groups key and normalize it to 'groups'."""
        if isinstance(data, dict) and "groups" not in data:
            for value in data.values():
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
        """Convert SSR data into the canonical WalmartOrder model."""
        items = []
        for group in self.groups:
            for item in group.items:
                line_price = None
                if item.price_info and item.price_info.line_price:
                    line_price = item.price_info.line_price.value
                items.append(
                    WalmartItem(
                        name=item.product_info.name,
                        quantity=item.quantity,
                        line_price=line_price,
                    ),
                )
        subtotal = (
            self.price_details.sub_total.value
            if self.price_details and self.price_details.sub_total
            else None
        )
        total = (
            self.price_details.grand_total.value
            if self.price_details and self.price_details.grand_total
            else None
        )
        return WalmartOrder(
            order_id=self.id,
            items=items,
            subtotal=subtotal,
            total=total,
        )


class GrocyProduct(BaseModel):
    """A product from the Grocy inventory."""

    id: int
    name: str


class ProductMatch(BaseModel):
    """A Walmart item matched to a Grocy product by fuzzy name matching."""

    walmart_item: WalmartItem
    grocy_product: GrocyProduct
    score: int


class ImportResult(BaseModel):
    """Result of importing a single Walmart order into Grocy."""

    order_id: str
    matched: list[ProductMatch]
    unmatched: list[WalmartItem]
