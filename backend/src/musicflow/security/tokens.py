from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Protocol

import jwt
from jwt import PyJWK, PyJWKClient
from jwt.exceptions import PyJWKClientConnectionError, PyJWKClientError, PyJWTError

from musicflow.core.config import Settings

ALLOWED_JWT_ALGORITHMS = ["RS256"]
MAX_BEARER_TOKEN_LENGTH = 8192
MAX_SUBJECT_LENGTH = 255


class InvalidAccessTokenError(Exception):
    """Raised when a bearer token cannot represent an authenticated principal."""


class IdentityProviderUnavailableError(Exception):
    """Raised when a signing key is unavailable because the trusted provider failed."""


class SigningKeyResolver(Protocol):
    def get_signing_key_from_jwt(self, token: str) -> PyJWK:
        """Resolve the signing key selected by the token header."""


@dataclass(frozen=True, slots=True)
class ExternalPrincipal:
    issuer: str
    subject: str


class AccessTokenVerifier:
    def __init__(
        self,
        settings: Settings,
        *,
        key_resolver: SigningKeyResolver | None = None,
    ) -> None:
        self._issuer = settings.oidc_issuer
        self._audience = settings.oidc_audience
        self._clock_skew_seconds = settings.oidc_clock_skew_seconds
        self._key_resolver = key_resolver or PyJWKClient(
            settings.oidc_jwks_url,
            cache_jwk_set=True,
            lifespan=settings.oidc_jwks_cache_seconds,
        )

    async def verify(self, token: str) -> ExternalPrincipal:
        if not token or len(token) > MAX_BEARER_TOKEN_LENGTH:
            raise InvalidAccessTokenError from None

        try:
            signing_key = await asyncio.to_thread(
                self._key_resolver.get_signing_key_from_jwt,
                token,
            )
            claims = jwt.decode(
                token,
                signing_key.key,
                algorithms=ALLOWED_JWT_ALGORITHMS,
                audience=self._audience,
                issuer=self._issuer,
                leeway=self._clock_skew_seconds,
                options={
                    "require": ["exp", "iat", "iss", "aud", "sub"],
                    "enforce_minimum_key_length": True,
                },
            )
        except PyJWKClientConnectionError as error:
            raise IdentityProviderUnavailableError from error
        except (PyJWKClientError, PyJWTError, TypeError, ValueError) as error:
            raise InvalidAccessTokenError from error

        subject = claims.get("sub")
        if not isinstance(subject, str) or not subject or len(subject) > MAX_SUBJECT_LENGTH:
            raise InvalidAccessTokenError from None

        return ExternalPrincipal(issuer=self._issuer, subject=subject)
