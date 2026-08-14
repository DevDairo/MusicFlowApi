from __future__ import annotations

import logging
from uuid import UUID

from musicflow.core.logging import log_event

_logger = logging.getLogger(__name__)


class ResourceOwnershipError(Exception):
    """Raised when an authenticated user does not own a private resource."""


def require_resource_owner(*, authenticated_user_id: UUID, owner_id: UUID) -> None:
    if authenticated_user_id != owner_id:
        log_event(
            _logger,
            logging.WARNING,
            "authorization_denied",
            reason="resource_owner_mismatch",
            authenticated_user_id=str(authenticated_user_id),
            owner_id=str(owner_id),
        )
        raise ResourceOwnershipError
