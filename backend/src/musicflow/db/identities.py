from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import Column, DateTime, String, Table, UniqueConstraint, Uuid, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncEngine

from musicflow.db.base import metadata
from musicflow.security.tokens import ExternalPrincipal

user_identities = Table(
    "user_identities",
    metadata,
    Column("id", Uuid(as_uuid=True), primary_key=True),
    Column("issuer", String(512), nullable=False),
    Column("subject", String(255), nullable=False),
    Column("created_at", DateTime(timezone=True), nullable=False),
    UniqueConstraint("issuer", "subject"),
)


@dataclass(frozen=True, slots=True)
class InternalIdentity:
    id: UUID


async def resolve_internal_identity(
    engine: AsyncEngine,
    principal: ExternalPrincipal,
) -> InternalIdentity:
    candidate_id = uuid4()
    statement = (
        insert(user_identities)
        .values(
            id=candidate_id,
            issuer=principal.issuer,
            subject=principal.subject,
            created_at=datetime.now(UTC),
        )
        .on_conflict_do_nothing(index_elements=["issuer", "subject"])
        .returning(user_identities.c.id)
    )

    async with engine.begin() as connection:
        inserted_id = (await connection.execute(statement)).scalar_one_or_none()
        if inserted_id is not None:
            return InternalIdentity(id=inserted_id)

        existing_id = (
            await connection.execute(
                select(user_identities.c.id).where(
                    user_identities.c.issuer == principal.issuer,
                    user_identities.c.subject == principal.subject,
                )
            )
        ).scalar_one()

    return InternalIdentity(id=existing_id)
