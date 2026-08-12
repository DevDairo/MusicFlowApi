from __future__ import annotations

from uuid import UUID

from fastapi.testclient import TestClient

from musicflow.api.main import create_app
from musicflow.api.middleware import CORRELATION_HEADER
from musicflow.core.config import Settings


def test_valid_correlation_id_is_returned(settings: Settings) -> None:
    app = create_app(settings)

    with TestClient(app) as client:
        response = client.get("/health/live", headers={CORRELATION_HEADER: "client-request-42"})

    assert response.headers[CORRELATION_HEADER] == "client-request-42"


def test_invalid_correlation_id_is_replaced(settings: Settings) -> None:
    app = create_app(settings)

    with TestClient(app) as client:
        response = client.get("/health/live", headers={CORRELATION_HEADER: "invalid value!"})

    generated_id = response.headers[CORRELATION_HEADER]
    assert generated_id != "invalid value!"
    assert str(UUID(generated_id)) == generated_id
