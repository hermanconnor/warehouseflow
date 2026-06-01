import logging
import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status
from api.models import LowStockProduct, MonthlySalesRow
from api.db import get_db

logger = logging.getLogger("warehouseflow.reports")

router = APIRouter(prefix="/reports", tags=["Reports"])


@router.get("/low-stock", response_model=list[LowStockProduct])
async def get_low_stock(
    threshold: int = Query(
        default=10, ge=0, description="The inventory ceiling to flag items as low stock"),
    db: asyncpg.Connection = Depends(get_db)
):
    """Retrieves items whose quantities fall at or below the specified threshold."""
    try:
        rows = await db.fetch("SELECT * FROM get_low_stock_products($1);", threshold)

        # Return the rows directly, Pydantic automatically maps the fields using validation_alias
        return rows

    except Exception as e:
        logger.error(
            f"Failed to fetch low stock metrics: {e}", exc_info=True)

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while fetching the low stock report."
        )


@router.get("/monthly-sales", response_model=list[MonthlySalesRow])
async def get_monthly_sales(
    month: int = Query(..., ge=1, le=12,
                       description="Target month integer (1-12)"),
    year: int = Query(..., ge=1900, le=2100,
                      description="Target year four-digit integer"),
    db: asyncpg.Connection = Depends(get_db)
):
    """Compiles total items sold and financial revenues aggregated by product for a given month."""
    try:
        rows = await db.fetch("SELECT * FROM get_monthly_sales($1, $2);", month, year)

        # No dictionary casting needed, Pydantic reads the asyncpg record rows directly
        return rows

    except Exception as e:
        logger.error(
            f"Failed to extract monthly performance metrics: {e}", exc_info=True)

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while compiling the monthly sales metrics report."
        )
