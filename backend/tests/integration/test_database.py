from __future__ import annotations

import asyncio

import pytest
from sqlalchemy import text

from musicflow.core.config import Settings
from musicflow.db.engine import check_database, create_database_engine
from musicflow.db.identities import resolve_internal_identity
from musicflow.security.tokens import ExternalPrincipal


@pytest.mark.integration
def test_database_probe_and_migration_head(integration_settings: Settings) -> None:
    async def verify() -> None:
        engine = create_database_engine(integration_settings)
        try:
            await check_database(engine, timeout_seconds=2)
            async with engine.connect() as connection:
                result = await connection.execute(text("SELECT version_num FROM alembic_version"))
                assert result.scalar_one() == "20260814_0002"
        finally:
            await engine.dispose()

    asyncio.run(verify())


@pytest.mark.integration
def test_external_principal_resolves_to_stable_internal_identity(
    integration_settings: Settings,
) -> None:
    async def verify() -> None:
        engine = create_database_engine(integration_settings)
        principal = ExternalPrincipal(
            issuer=integration_settings.oidc_issuer,
            subject="integration-test-subject",
        )
        try:
            first = await resolve_internal_identity(engine, principal)
            second = await resolve_internal_identity(engine, principal)
            another = await resolve_internal_identity(
                engine,
                ExternalPrincipal(
                    issuer=principal.issuer,
                    subject="another-integration-test-subject",
                ),
            )
        finally:
            await engine.dispose()

        assert first == second
        assert first != another

    asyncio.run(verify())
