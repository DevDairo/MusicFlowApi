from __future__ import annotations

import asyncio
import logging
import signal
import time
from contextlib import suppress
from pathlib import Path

from sqlalchemy.exc import SQLAlchemyError

from musicflow import __version__
from musicflow.core.config import Settings, get_settings
from musicflow.core.logging import configure_logging, log_event
from musicflow.db.engine import check_database, create_database_engine

_logger = logging.getLogger(__name__)


def _write_heartbeat(path: Path) -> None:
    temporary_path = path.with_suffix(".tmp")
    temporary_path.write_text(str(time.time()), encoding="utf-8")
    temporary_path.replace(path)


def _remove_heartbeat(path: Path) -> None:
    path.unlink(missing_ok=True)
    path.with_suffix(".tmp").unlink(missing_ok=True)


async def _wait_for_next_probe(stop_event: asyncio.Event, interval_seconds: float) -> None:
    with suppress(TimeoutError):
        await asyncio.wait_for(stop_event.wait(), timeout=interval_seconds)


def _install_signal_handlers(stop_event: asyncio.Event) -> None:
    loop = asyncio.get_running_loop()
    for current_signal in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(current_signal, stop_event.set)
        except NotImplementedError:
            signal.signal(current_signal, lambda *_: stop_event.set())


async def run_worker(settings: Settings) -> None:
    configure_logging(settings)
    engine = create_database_engine(settings)
    stop_event = asyncio.Event()
    _install_signal_handlers(stop_event)
    database_available: bool | None = None

    log_event(_logger, logging.INFO, "worker_started", version=__version__)
    try:
        while not stop_event.is_set():
            try:
                await check_database(
                    engine,
                    timeout_seconds=settings.db_connect_timeout_seconds,
                )
                _write_heartbeat(settings.worker_health_file)
                if database_available is not True:
                    log_event(_logger, logging.INFO, "worker_database_available")
                database_available = True
            except OSError, TimeoutError, SQLAlchemyError:
                _remove_heartbeat(settings.worker_health_file)
                if database_available is not False:
                    log_event(_logger, logging.WARNING, "worker_database_unavailable")
                database_available = False

            await _wait_for_next_probe(stop_event, settings.worker_heartbeat_seconds)
    finally:
        _remove_heartbeat(settings.worker_health_file)
        await engine.dispose()
        log_event(_logger, logging.INFO, "worker_stopped")


def main() -> None:
    asyncio.run(run_worker(get_settings()))


if __name__ == "__main__":
    main()
