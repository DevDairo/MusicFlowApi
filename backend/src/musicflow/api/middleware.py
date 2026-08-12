from __future__ import annotations

import logging
import re
import time
from collections.abc import Awaitable, Callable
from uuid import uuid4

from fastapi import Request, Response

from musicflow.core.logging import log_event, reset_correlation_id, set_correlation_id

CORRELATION_HEADER = "X-Correlation-ID"
_VALID_CORRELATION_ID = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
_logger = logging.getLogger(__name__)


def _resolve_correlation_id(request: Request) -> str:
    candidate = request.headers.get(CORRELATION_HEADER, "")
    if _VALID_CORRELATION_ID.fullmatch(candidate):
        return candidate
    return str(uuid4())


async def correlation_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    correlation_id = _resolve_correlation_id(request)
    token = set_correlation_id(correlation_id)
    started = time.perf_counter()

    try:
        response = await call_next(request)
        response.headers[CORRELATION_HEADER] = correlation_id
        log_event(
            _logger,
            logging.INFO,
            "http_request_completed",
            method=request.method,
            path=request.url.path,
            status_code=response.status_code,
            duration_ms=round((time.perf_counter() - started) * 1000, 2),
        )
        return response
    except Exception:
        log_event(
            _logger,
            logging.ERROR,
            "http_request_failed",
            exc_info=True,
            method=request.method,
            path=request.url.path,
            duration_ms=round((time.perf_counter() - started) * 1000, 2),
        )
        raise
    finally:
        reset_correlation_id(token)
