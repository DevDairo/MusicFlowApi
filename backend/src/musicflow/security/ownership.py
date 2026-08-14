from __future__ import annotations

from uuid import UUID


class ResourceOwnershipError(Exception):
    """Raised when an authenticated user does not own a private resource."""


def require_resource_owner(*, authenticated_user_id: UUID, owner_id: UUID) -> None:
    if authenticated_user_id != owner_id:
        raise ResourceOwnershipError
