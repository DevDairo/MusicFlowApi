"""Add stable internal user identities.

Revision ID: 20260814_0002
Revises: 20260812_0001
Create Date: 2026-08-14
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260814_0002"
down_revision: str | Sequence[str] | None = "20260812_0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "user_identities",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("issuer", sa.String(length=512), nullable=False),
        sa.Column("subject", sa.String(length=255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user_identities")),
        sa.UniqueConstraint(
            "issuer",
            "subject",
            name=op.f("uq_user_identities_issuer"),
        ),
    )


def downgrade() -> None:
    op.drop_table("user_identities")
