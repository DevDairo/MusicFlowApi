from __future__ import annotations

from uuid import uuid4

import pytest

from musicflow.security.ownership import ResourceOwnershipError, require_resource_owner


def test_resource_owner_is_authorized() -> None:
    owner_id = uuid4()

    require_resource_owner(authenticated_user_id=owner_id, owner_id=owner_id)


def test_another_user_is_rejected(monkeypatch) -> None:
    events: list[tuple[str, dict[str, object]]] = []

    def record_event(_logger, _level, event: str, **fields: object) -> None:
        events.append((event, fields))

    monkeypatch.setattr("musicflow.security.ownership.log_event", record_event)
    authenticated_user_id = uuid4()
    owner_id = uuid4()

    with pytest.raises(ResourceOwnershipError):
        require_resource_owner(
            authenticated_user_id=authenticated_user_id,
            owner_id=owner_id,
        )

    assert events == [
        (
            "authorization_denied",
            {
                "reason": "resource_owner_mismatch",
                "authenticated_user_id": str(authenticated_user_id),
                "owner_id": str(owner_id),
            },
        )
    ]
