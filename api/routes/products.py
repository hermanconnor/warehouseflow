import logging
import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status
from api.db import get_db
from api.models import ProductResponse

logger = logging.getLogger("warehouseflow.products")

router = APIRouter(prefix="/products", tags=["Products"])


@router.get("/", response_model=list[ProductResponse])
async def get_products(db: asyncpg.Connection = Depends(get_db)):
    """Retrieves all products from the core catalog sorted by product_id."""
    try:
        rows = await db.fetch("SELECT * FROM products ORDER BY product_id;")

        return rows

    except Exception as e:
        logger.error(f"Failed to fetch products: {e}", exc_info=True)

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while fetching products."
        )
