from __future__ import annotations

from uuid import UUID

from fastapi.testclient import TestClient

import musicflow.api.dependencies as dependencies_module
from musicflow.api.main import create_app
from musicflow.core.config import Settings
from musicflow.db.identities import InternalIdentity
from musicflow.security.tokens import (
    ExternalPrincipal,
    IdentityProviderUnavailableError,
    InvalidAccessTokenError,
)

INTERNAL_USER_ID = UUID("8f5a6eb8-68e0-4ddd-9660-0c82a32f8af5")


class ValidVerifier:
    async def verify(self, _token: str) -> ExternalPrincipal:
        return ExternalPrincipal(
            issuer="https://identity.test/realms/musicflow",
            subject="keycloak-subject-1",
        )


class InvalidVerifier:
    async def verify(self, _token: str) -> ExternalPrincipal:
        raise InvalidAccessTokenError


class UnavailableVerifier:
    async def verify(self, _token: str) -> ExternalPrincipal:
        raise IdentityProviderUnavailableError


def test_me_rejects_missing_bearer_token(settings: Settings, monkeypatch) -> None:
    events: list[tuple[str, dict[str, object]]] = []

    def record_event(_logger, _level, event: str, **fields: object) -> None:
        events.append((event, fields))

    monkeypatch.setattr(dependencies_module, "log_event", record_event)
    app = create_app(settings)

    with TestClient(app) as client:
        response = client.get("/v1/me")

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert response.json()["detail"]["code"] == "invalid_access_token"
    assert ("authentication_rejected", {"reason": "missing_bearer"}) in events


def test_me_rejects_invalid_access_token(settings: Settings, monkeypatch) -> None:
    events: list[tuple[str, dict[str, object]]] = []

    def record_event(_logger, _level, event: str, **fields: object) -> None:
        events.append((event, fields))

    monkeypatch.setattr(dependencies_module, "log_event", record_event)
    app = create_app(settings)

    with TestClient(app) as client:
        app.state.access_token_verifier = InvalidVerifier()
        response = client.get(
            "/v1/me",
            headers={"Authorization": "Bearer sensitive-invalid-token"},
        )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert ("authentication_rejected", {"reason": "invalid_access_token"}) in events
    assert "sensitive-invalid-token" not in repr(events)


def test_me_reports_identity_provider_unavailability(settings: Settings) -> None:
    app = create_app(settings)

    with TestClient(app) as client:
        app.state.access_token_verifier = UnavailableVerifier()
        response = client.get("/v1/me", headers={"Authorization": "Bearer valid"})

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "identity_provider_unavailable"


def test_me_returns_stable_internal_identity(
    settings: Settings,
    monkeypatch,
) -> None:
    events: list[tuple[str, dict[str, object]]] = []

    async def resolve_identity(*_args, **_kwargs) -> InternalIdentity:
        return InternalIdentity(id=INTERNAL_USER_ID)

    def record_event(_logger, _level, event: str, **fields: object) -> None:
        events.append((event, fields))

    monkeypatch.setattr(dependencies_module, "resolve_internal_identity", resolve_identity)
    monkeypatch.setattr(dependencies_module, "log_event", record_event)
    app = create_app(settings)

    with TestClient(app) as client:
        app.state.access_token_verifier = ValidVerifier()
        response = client.get("/v1/me", headers={"Authorization": "Bearer valid"})

    assert response.status_code == 200
    assert response.json() == {"id": str(INTERNAL_USER_ID)}
    assert (
        "authentication_succeeded",
        {"internal_user_id": str(INTERNAL_USER_ID)},
    ) in events


def test_origin_rate_limit_returns_429_without_limiting_liveness(
    settings: Settings,
) -> None:
    limited_settings = settings.model_copy(
        update={
            "rate_limit_origin_requests": 2,
            "rate_limit_identity_requests": 10,
            "trust_cloudflare_connecting_ip": True,
        }
    )
    app = create_app(limited_settings)
    headers = {"CF-Connecting-IP": "203.0.113.10"}

    with TestClient(app) as client:
        assert client.get("/v1/me", headers=headers).status_code == 401
        assert client.get("/v1/me", headers=headers).status_code == 401
        response = client.get("/v1/me", headers=headers)
        liveness = client.get("/health/live", headers=headers)

    assert response.status_code == 429
    assert response.json()["detail"]["code"] == "rate_limit_exceeded"
    assert 1 <= int(response.headers["retry-after"]) <= 60
    assert response.headers["x-correlation-id"]
    assert liveness.status_code == 200


def test_authenticated_identity_has_an_independent_rate_limit(
    settings: Settings,
    monkeypatch,
) -> None:
    async def resolve_identity(*_args, **_kwargs) -> InternalIdentity:
        return InternalIdentity(id=INTERNAL_USER_ID)

    monkeypatch.setattr(dependencies_module, "resolve_internal_identity", resolve_identity)
    limited_settings = settings.model_copy(
        update={
            "rate_limit_origin_requests": 10,
            "rate_limit_identity_requests": 2,
        }
    )
    app = create_app(limited_settings)
    headers = {"Authorization": "Bearer valid"}

    with TestClient(app) as client:
        app.state.access_token_verifier = ValidVerifier()
        assert client.get("/v1/me", headers=headers).status_code == 200
        assert client.get("/v1/me", headers=headers).status_code == 200
        response = client.get("/v1/me", headers=headers)

    assert response.status_code == 429
    assert response.json()["detail"]["code"] == "rate_limit_exceeded"
