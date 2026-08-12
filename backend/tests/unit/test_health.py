from __future__ import annotations

from fastapi.testclient import TestClient

import musicflow.api.routes.health as health_module
from musicflow.api.main import create_app
from musicflow.core.config import Settings


def test_liveness_does_not_require_database(settings: Settings) -> None:
    app = create_app(settings)

    with TestClient(app) as client:
        response = client.get("/health/live")

    assert response.status_code == 200
    assert response.json() == {"status": "alive", "checks": None}


def test_readiness_reports_available_database(
    settings: Settings,
    monkeypatch,
) -> None:
    async def successful_probe(*_args, **_kwargs) -> None:
        return None

    monkeypatch.setattr(health_module, "check_database", successful_probe)
    app = create_app(settings)

    with TestClient(app) as client:
        response = client.get("/health/ready")

    assert response.status_code == 200
    assert response.json() == {"status": "ready", "checks": {"database": "available"}}


def test_readiness_hides_database_error_details(
    settings: Settings,
    monkeypatch,
) -> None:
    async def failed_probe(*_args, **_kwargs) -> None:
        raise TimeoutError("sensitive connection detail")

    monkeypatch.setattr(health_module, "check_database", failed_probe)
    app = create_app(settings)

    with TestClient(app) as client:
        response = client.get("/health/ready")

    assert response.status_code == 503
    assert response.json() == {
        "status": "not_ready",
        "checks": {"database": "unavailable"},
    }
    assert "sensitive" not in response.text
