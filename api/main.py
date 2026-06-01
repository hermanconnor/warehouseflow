import logging
from fastapi import FastAPI, status
from api.db import lifespan
from api.routes import products, orders, inventory, reports


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)

logger = logging.getLogger("warehouseflow.main")

app = FastAPI(
    title="WarehouseFlow API",
    description="Inventory and order management system",
    version="1.0.0",
    lifespan=lifespan
)

app.include_router(products.router)
app.include_router(orders.router)
app.include_router(inventory.router)
app.include_router(reports.router)


@app.get("/health", status_code=status.HTTP_200_OK, tags=["System"])
async def health_check():
    """Simple container and monitoring health heartbeat endpoint."""

    return {
        "status": "healthy",
        "service": "WarehouseFlow Core Engine"
    }
