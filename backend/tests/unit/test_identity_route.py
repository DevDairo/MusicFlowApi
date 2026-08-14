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


def test_me_rejects_missing_bearer_token(settings: Settings) -> None:
    app = create_app(settings)

    with TestClient(app) as client:
        response = client.get("/v1/me")

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert response.json()["detail"]["code"] == "invalid_access_token"


def test_me_rejects_invalid_access_token(settings: Settings) -> None:
    app = create_app(settings)

    with TestClient(app) as client:
        app.state.access_token_verifier = InvalidVerifier()
        response = client.get("/v1/me", headers={"Authorization": "Bearer invalid"})

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


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
    async def resolve_identity(*_args, **_kwargs) -> InternalIdentity:
        return InternalIdentity(id=INTERNAL_USER_ID)

    monkeypatch.setattr(dependencies_module, "resolve_internal_identity", resolve_identity)
    app = create_app(settings)

    with TestClient(app) as client:
        app.state.access_token_verifier = ValidVerifier()
        response = client.get("/v1/me", headers={"Authorization": "Bearer valid"})

    assert response.status_code == 200
    assert response.json() == {"id": str(INTERNAL_USER_ID)}
