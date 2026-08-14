from __future__ import annotations

import logging
from typing import Annotated

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


async def get_current_identity(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> InternalIdentity:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _authentication_error()

    try:
        principal = await request.app.state.access_token_verifier.verify(credentials.credentials)
    except InvalidAccessTokenError:
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
        return await resolve_internal_identity(request.app.state.database_engine, principal)
    except SQLAlchemyError:
        log_event(_logger, logging.ERROR, "identity_resolution_failed", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "identity_store_unavailable",
                "message": "Identity resolution is temporarily unavailable.",
            },
        ) from None
