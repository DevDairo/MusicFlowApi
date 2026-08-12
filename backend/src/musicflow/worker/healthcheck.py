from __future__ import annotations

import sys
import time
from pathlib import Path

from musicflow.core.config import get_settings


def heartbeat_is_fresh(
    path: Path,
    *,
    max_age_seconds: float,
    now: float | None = None,
) -> bool:
    try:
        heartbeat = float(path.read_text(encoding="utf-8"))
    except OSError, ValueError:
        return False

    current_time = time.time() if now is None else now
    age = current_time - heartbeat
    return 0 <= age <= max_age_seconds


def main() -> int:
    settings = get_settings()
    healthy = heartbeat_is_fresh(
        settings.worker_health_file,
        max_age_seconds=settings.worker_heartbeat_seconds * 3,
    )
    return 0 if healthy else 1


if __name__ == "__main__":
    sys.exit(main())
