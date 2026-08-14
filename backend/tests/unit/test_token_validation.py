from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from musicflow.core.config import Settings
from musicflow.security.tokens import (
    MAX_BEARER_TOKEN_LENGTH,
    AccessTokenVerifier,
    ExternalPrincipal,
    InvalidAccessTokenError,
)


class StaticKeyResolver:
    def __init__(self, public_key) -> None:
        self._public_key = public_key

    def get_signing_key_from_jwt(self, _token: str):
        return SimpleNamespace(key=self._public_key)


@pytest.fixture(scope="module")
def rsa_key_pair():
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return private_key, private_key.public_key()


def build_token(
    settings: Settings,
    private_key,
    *,
    overrides: dict[str, object] | None = None,
) -> str:
    now = datetime.now(UTC)
    claims: dict[str, object] = {
        "iss": settings.oidc_issuer,
        "aud": settings.oidc_audience,
        "sub": "keycloak-subject-1",
        "iat": now,
        "exp": now + timedelta(minutes=5),
    }
    claims.update(overrides or {})
    return jwt.encode(claims, private_key, algorithm="RS256", headers={"kid": "test-key"})


def test_valid_access_token_returns_external_principal(
    settings: Settings,
    rsa_key_pair,
) -> None:
    private_key, public_key = rsa_key_pair
    verifier = AccessTokenVerifier(settings, key_resolver=StaticKeyResolver(public_key))

    principal = asyncio.run(verifier.verify(build_token(settings, private_key)))

    assert principal == ExternalPrincipal(
        issuer=settings.oidc_issuer,
        subject="keycloak-subject-1",
    )


@pytest.mark.parametrize(
    "overrides",
    [
        {"iss": "https://untrusted.example/realms/musicflow"},
        {"aud": "another-api"},
        {"exp": datetime.now(UTC) - timedelta(minutes=1)},
        {"iat": datetime.now(UTC) + timedelta(minutes=5)},
        {"sub": ""},
    ],
)
def test_invalid_claims_are_rejected(
    settings: Settings,
    rsa_key_pair,
    overrides: dict[str, object],
) -> None:
    private_key, public_key = rsa_key_pair
    verifier = AccessTokenVerifier(settings, key_resolver=StaticKeyResolver(public_key))

    with pytest.raises(InvalidAccessTokenError):
        asyncio.run(verifier.verify(build_token(settings, private_key, overrides=overrides)))


def test_token_signed_by_another_key_is_rejected(settings: Settings, rsa_key_pair) -> None:
    private_key, _public_key = rsa_key_pair
    another_private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    verifier = AccessTokenVerifier(
        settings,
        key_resolver=StaticKeyResolver(another_private_key.public_key()),
    )

    with pytest.raises(InvalidAccessTokenError):
        asyncio.run(verifier.verify(build_token(settings, private_key)))


def test_expired_access_token_is_rejected(settings: Settings, rsa_key_pair) -> None:
    private_key, public_key = rsa_key_pair
    verifier = AccessTokenVerifier(settings, key_resolver=StaticKeyResolver(public_key))
    expired_token = build_token(
        settings,
        private_key,
        overrides={"exp": datetime.now(UTC) - timedelta(minutes=1)},
    )

    with pytest.raises(InvalidAccessTokenError):
        asyncio.run(verifier.verify(expired_token))


def test_excessively_long_token_is_rejected_before_key_resolution(settings: Settings) -> None:
    class FailingResolver:
        def get_signing_key_from_jwt(self, _token: str):
            raise AssertionError("resolver must not be called")

    verifier = AccessTokenVerifier(settings, key_resolver=FailingResolver())

    with pytest.raises(InvalidAccessTokenError):
        asyncio.run(verifier.verify("x" * (MAX_BEARER_TOKEN_LENGTH + 1)))
