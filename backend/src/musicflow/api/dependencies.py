from __future__ import annotations

import logging
from ipaddress import ip_address
from typing import Annotated, Literal

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.exc import SQLAlchemyError

from musicflow.core.logging import log_event
from musicflow.db.identities import InternalIdentity, resolve_internal_identity
from musicflow.security.tokens import (
    IdentityProviderUnavailableError,
    InvalidAccessTokenError,
)

_bearer = HTTPBearer(auto_error=False)
_logger = logging.getLogger(__name__)


def _authentication_error() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail={
            "code": "invalid_access_token",
            "message": "A valid bearer access token is required.",
        },
        headers={"WWW-Authenticate": "Bearer"},
    )


def _rate_limit_error(retry_after_seconds: int) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail={
            "code": "rate_limit_exceeded",
            "message": "Too many authentication requests. Try again later.",
        },
        headers={"Retry-After": str(retry_after_seconds)},
    )


def _client_origin(request: Request) -> str:
    settings = request.app.state.settings
    if settings.trust_cloudflare_connecting_ip:
        candidate = request.headers.get("CF-Connecting-IP", "")
        try:
            return str(ip_address(candidate))
        except ValueError:
            pass

    if request.client is not None:
        return request.client.host
    return "unknown"


async def _enforce_rate_limit(
    request: Request,
    *,
    scope: Literal["origin", "identity"],
    key: str,
) -> None:
    if not request.app.state.settings.rate_limit_enabled:
        return

    limiter = (
        request.app.state.auth_origin_rate_limiter
        if scope == "origin"
        else request.app.state.auth_identity_rate_limiter
    )
    decision = await limiter.consume(key)
    if decision.allowed:
        return

    retry_after_seconds = decision.retry_after_seconds or 1
    log_event(
        _logger,
        logging.WARNING,
        "authentication_rate_limited",
        scope=scope,
        retry_after_seconds=retry_after_seconds,
    )
    raise _rate_limit_error(retry_after_seconds)


async def get_current_identity(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> InternalIdentity:
    await _enforce_rate_limit(request, scope="origin", key=_client_origin(request))

    if credentials is None or credentials.scheme.lower() != "bearer":
        log_event(
            _logger,
            logging.WARNING,
            "authentication_rejected",
            reason="missing_bearer",
        )
        raise _authentication_error()

    try:
        principal = await request.app.state.access_token_verifier.verify(credentials.credentials)
    except InvalidAccessTokenError:
        log_event(
            _logger,
            logging.WARNING,
            "authentication_rejected",
            reason="invalid_access_token",
        )
        raise _authentication_error() from None
    except IdentityProviderUnavailableError:
        log_event(_logger, logging.WARNING, "identity_provider_unavailable")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "identity_provider_unavailable",
                "message": "Identity validation is temporarily unavailable.",
            },
        ) from None

    try:
        identity = await resolve_internal_identity(request.app.state.database_engine, principal)
    except SQLAlchemyError:
        log_event(_logger, logging.ERROR, "identity_resolution_failed", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "identity_store_unavailable",
                "message": "Identity resolution is temporarily unavailable.",
            },
        ) from None

    await _enforce_rate_limit(request, scope="identity", key=str(identity.id))
    log_event(
        _logger,
        logging.INFO,
        "authentication_succeeded",
        internal_user_id=str(identity.id),
    )
    return identity
