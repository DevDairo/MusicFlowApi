from __future__ import annotations

import asyncio

import pytest
from sqlalchemy import text

from musicflow.core.config import Settings
from musicflow.db.engine import check_database, create_database_engine


@pytest.mark.integration
def test_database_probe_and_migration_head(integration_settings: Settings) -> None:
    async def verify() -> None:
        engine = create_database_engine(integration_settings)
        try:
            await check_database(engine, timeout_seconds=2)
            async with engine.connect() as connection:
                result = await connection.execute(text("SELECT version_num FROM alembic_version"))
                assert result.scalar_one() == "20260812_0001"
        finally:
            await engine.dispose()

    asyncio.run(verify())
