from __future__ import annotations

import asyncio

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

from musicflow.core.config import Settings


def create_database_engine(settings: Settings) -> AsyncEngine:
    return create_async_engine(
        settings.database_url,
        pool_pre_ping=True,
    )


async def check_database(engine: AsyncEngine, *, timeout_seconds: float) -> None:
    async def probe() -> None:
        async with engine.connect() as connection:
            result = await connection.execute(text("SELECT 1"))
            if result.scalar_one() != 1:
                raise RuntimeError("Unexpected database health response.")

    await asyncio.wait_for(probe(), timeout=timeout_seconds)
