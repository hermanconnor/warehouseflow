import logging
import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status
from api.models import ReceiveInventoryRequest
from api.db import get_db

logger = logging.getLogger("warehouseflow.inventory")

router = APIRouter(prefix="/inventory", tags=["Inventory"])


@router.post("/receive", status_code=status.HTTP_200_OK)
async def receive_inventory(
    request: ReceiveInventoryRequest,
    db: asyncpg.Connection = Depends(get_db)
):
    """Restocks inventory for a specific product item."""
    try:
        async with db.transaction():

            await db.execute(
                "SELECT set_config('warehouseflow.audit_reason', $1, true);",
                request.reason
            )

            # Call inventory procedure inside the exact same transaction context
            await db.execute(
                "CALL receive_inventory($1, $2);",
                request.product_id,
                request.quantity
            )

        return {
            "success": True,
            "message": f"Successfully received {request.quantity} units for product {request.product_id}."
        }

    except asyncpg.exceptions.RaiseError as e:
        # Catch custom database validation exceptions gracefully (e.g., quantity <= 0)
        logger.warning(
            f"Inventory adjustment rejected by database: {e.message}")

        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=e.message
        )

    except Exception as e:
        # Catch unexpected infrastructure errors
        logger.error(
            f"An unexpected error occurred during stock modification: {e}", exc_info=True)

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while modifying stock balances."
        )
