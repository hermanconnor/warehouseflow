import json
import logging
import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status
from api.db import get_db
from api.models import CreateOrderRequest, OrderResponse


logger = logging.getLogger("warehouseflow.orders")

router = APIRouter(prefix="/orders", tags=["Orders"])


@router.post("/", response_model=OrderResponse, status_code=status.HTTP_201_CREATED)
async def create_order(
    request: CreateOrderRequest,
    db: asyncpg.Connection = Depends(get_db)
):
    """Submits a new customer checkout order."""
    items_payload = [item.model_dump() for item in request.items]

    try:
       # 1. Execute the CALL with only the two IN parameters
        result = await db.fetchrow(
            "CALL create_order($1::int, $2::jsonb, $3);",
            request.customer_id,
            json.dumps(items_payload),
            None
        )

        # 2. Check for your exact parameter name 'p_order_id'
        if not result or "p_order_id" not in result:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database failed to return a valid transaction confirmation identifier."
            )

        # 3. Extract the new ID safely
        new_order_id = result["p_order_id"]
        return OrderResponse(
            order_id=new_order_id,
            message=f"Order {new_order_id} created successfully."
        )

    except asyncpg.exceptions.RaiseError as e:
        # Catch explicit database exceptions (e.g., RAISE EXCEPTION 'Insufficient stock')
        logger.warning(
            f"Order checkout validation rejected by database: {e.message}")

        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=e.message
        )

    except Exception as e:
        # Handle structural query exceptions or unexpected system errors
        logger.error(
            f"An unexpected error occurred during checkout lifecycle: {e}", exc_info=True)

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred during order transaction."
        )
