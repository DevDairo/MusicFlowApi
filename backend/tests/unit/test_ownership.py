from __future__ import annotations

from uuid import uuid4

import pytest

from musicflow.security.ownership import ResourceOwnershipError, require_resource_owner


def test_resource_owner_is_authorized() -> None:
    owner_id = uuid4()

    require_resource_owner(authenticated_user_id=owner_id, owner_id=owner_id)


def test_another_user_is_rejected() -> None:
    with pytest.raises(ResourceOwnershipError):
        require_resource_owner(authenticated_user_id=uuid4(), owner_id=uuid4())
