from __future__ import annotations

from pathlib import Path

from musicflow.worker.healthcheck import heartbeat_is_fresh


def test_fresh_heartbeat_is_healthy(tmp_path: Path) -> None:
    health_file = tmp_path / "worker-health"
    health_file.write_text("100.0", encoding="utf-8")

    assert heartbeat_is_fresh(health_file, max_age_seconds=15, now=110.0)


def test_missing_invalid_or_stale_heartbeat_is_unhealthy(tmp_path: Path) -> None:
    health_file = tmp_path / "worker-health"
    assert not heartbeat_is_fresh(health_file, max_age_seconds=15, now=110.0)

    health_file.write_text("not-a-timestamp", encoding="utf-8")
    assert not heartbeat_is_fresh(health_file, max_age_seconds=15, now=110.0)

    health_file.write_text("90.0", encoding="utf-8")
    assert not heartbeat_is_fresh(health_file, max_age_seconds=15, now=110.0)
