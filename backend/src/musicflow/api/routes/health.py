from __future__ import annotations

import logging
from typing import Literal

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy.exc import SQLAlchemyError

from musicflow.core.logging import log_event
from musicflow.db.engine import check_database

router = APIRouter(prefix="/health", tags=["health"])
_logger = logging.getLogger(__name__)


class HealthResponse(BaseModel):
    status: Literal["alive", "ready", "not_ready"]
    checks: dict[str, str] | None = None


@router.get("/live", response_model=HealthResponse)
async def liveness() -> HealthResponse:
    """Report process liveness without calling external dependencies."""

    return HealthResponse(status="alive")


@router.get(
    "/ready",
    response_model=HealthResponse,
    responses={503: {"model": HealthResponse}},
)
async def readiness(request: Request) -> HealthResponse | JSONResponse:
    """Report readiness only when the database can complete a bounded probe."""

    try:
        await check_database(
            request.app.state.database_engine,
            timeout_seconds=request.app.state.settings.db_connect_timeout_seconds,
        )
    except OSError, TimeoutError, SQLAlchemyError:
        log_event(_logger, logging.WARNING, "database_readiness_failed")
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "checks": {"database": "unavailable"}},
        )

    return HealthResponse(status="ready", checks={"database": "available"})
