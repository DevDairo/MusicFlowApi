from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from musicflow import __version__
from musicflow.api.middleware import correlation_middleware
from musicflow.api.routes.health import router as health_router
from musicflow.api.routes.identity import router as identity_router
from musicflow.core.config import Settings, get_settings
from musicflow.core.logging import configure_logging, log_event
from musicflow.db.engine import create_database_engine
from musicflow.security.tokens import AccessTokenVerifier

_logger = logging.getLogger(__name__)


def create_app(settings: Settings | None = None) -> FastAPI:
    resolved_settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        configure_logging(resolved_settings)
        app.state.settings = resolved_settings
        app.state.database_engine = create_database_engine(resolved_settings)
        app.state.access_token_verifier = AccessTokenVerifier(resolved_settings)
        log_event(_logger, logging.INFO, "api_started", version=__version__)
        try:
            yield
        finally:
            await app.state.database_engine.dispose()
            log_event(_logger, logging.INFO, "api_stopped")

    application = FastAPI(
        title="MusicFlow API",
        version=__version__,
        docs_url="/docs" if resolved_settings.environment.value != "production" else None,
        redoc_url=None,
        lifespan=lifespan,
    )
    application.middleware("http")(correlation_middleware)
    application.include_router(health_router)
    application.include_router(identity_router)
    return application


app = create_app()
