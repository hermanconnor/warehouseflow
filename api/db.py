from contextlib import asynccontextmanager
from typing import AsyncGenerator
import asyncpg
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field
from fastapi import FastAPI


class DbSettings(BaseSettings):
    # Map .env keys to typed variables using field aliases
    user: str = Field("warehouse_user", validation_alias="DB_USER")
    password: str = Field("warehouse_pass", validation_alias="DB_PASSWORD")
    name: str = Field("warehouseflow", validation_alias="DB_NAME")
    host: str = Field("localhost", validation_alias="DB_HOST")
    port: int = Field(5432, validation_alias="DB_PORT")

    # Automatically loads from a .env file if it exists
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def database_url(self) -> str:
        return f"postgresql://{self.user}:{self.password}@{self.host}:{self.port}/{self.name}"


# Single instance of configuration settings
settings = DbSettings()

# This placeholder will hold the connection pool object globally within the app state
db_pool: asyncpg.Pool | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manages the application database connection pool lifecycle."""
    global db_pool

    # 1. Everything BEFORE the yield runs on STARTUP
    db_pool = await asyncpg.create_pool(
        settings.database_url,
        min_size=2,
        max_size=10
    )
    print("🚀 Database connection pool initialized successfully.")

    yield

    # 2. Everything AFTER the yield runs on SHUTDOWN
    if db_pool:
        await db_pool.close()
        print("🛑 Database connection pool closed gracefully.")


async def get_db() -> AsyncGenerator[asyncpg.Connection, None]:
    """FastAPI Dependency that provides a database connection from the pool.

    Yields a connection for the duration of a request and automatically 
    releases it back to the pool when the request concludes.
    """
    if db_pool is None:
        raise RuntimeError("Database connection pool is not initialized.")

    async with db_pool.acquire() as connection:
        yield connection
