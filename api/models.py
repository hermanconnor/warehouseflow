from typing import Optional
from datetime import datetime
from decimal import Decimal
from pydantic import BaseModel, Field, ConfigDict


# --- Base Configuration ---
class ResponseModel(BaseModel):
    """Base model configured to read database attributes and asyncpg records automatically."""
    model_config = ConfigDict(from_attributes=True)


# --- Order Models ---
class OrderItem(BaseModel):
    product_id: int
    quantity: int = Field(..., gt=0, description="Must be greater than zero")


class CreateOrderRequest(BaseModel):
    customer_id: int
    items: list[OrderItem] = Field(..., min_length=1,
                                   description="Order must contain at least one item")


class OrderResponse(ResponseModel):
    order_id: int
    message: str = "Order created successfully"


# --- Inventory Models ---
class ReceiveInventoryRequest(BaseModel):
    product_id: int
    quantity: int = Field(..., gt=0,
                          description="Quantity to receive must be greater than zero")
    reason: str = Field(default="Supplier Shipment", max_length=255)


# --- Product Models ---
class ProductResponse(ResponseModel):
    product_id: int
    sku: str
    name: str
    price: Decimal
    quantity_in_stock: int
    created_at: datetime


# --- Report Models ---
class LowStockProduct(ResponseModel):
    # Map the database function's unique output aliases safely to clean API outputs
    product_id: int = Field(..., validation_alias="out_product_id")
    sku: str = Field(..., validation_alias="out_sku")
    name: str = Field(..., validation_alias="out_name")
    price: Decimal = Field(..., validation_alias="out_price")
    quantity_in_stock: int = Field(..., validation_alias="out_quantity_stock")


class MonthlySalesRow(ResponseModel):
    # Map the analytical database function's unique output prefixes
    product_id: int = Field(..., validation_alias="out_product_id")
    product_name: str = Field(..., validation_alias="out_product_name")
    total_units_sold: int = Field(..., validation_alias="out_total_units")
    total_revenue: Decimal = Field(..., validation_alias="out_total_revenue")
