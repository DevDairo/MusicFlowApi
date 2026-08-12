"""Create the initial schema baseline.

Revision ID: 20260812_0001
Revises:
Create Date: 2026-08-12
"""

from collections.abc import Sequence

revision: str = "20260812_0001"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Establish the baseline without premature business tables."""


def downgrade() -> None:
    """Remove the empty baseline."""
