from contextlib import asynccontextmanager
from fastapi import FastAPI
import asyncpg
from api import db


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 1. Runs on FastAPI startup: Initialize the connection pool once
    db.db_pool = await asyncpg.create_pool(
        db.settings.database_url,
        min_size=2,
        max_size=10
    )
    yield
    # 2. Runs on FastAPI shutdown: Clean up connections gracefully
    await db.db_pool.close()

app = FastAPI(lifespan=lifespan)
