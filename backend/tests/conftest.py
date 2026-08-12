from __future__ import annotations

import pytest
from pydantic import SecretStr

from musicflow.core.config import Environment, Settings


@pytest.fixture
def settings() -> Settings:
    return Settings(
        service_name="tests",
        environment=Environment.TEST,
        log_level="CRITICAL",
        db_host="postgres",
        db_port=5432,
        db_name="musicflow",
        db_user="musicflow",
        db_password=SecretStr("test-password-not-for-production"),
        db_connect_timeout_seconds=1,
        worker_heartbeat_seconds=5,
    )


@pytest.fixture
def integration_settings() -> Settings:
    return Settings()  # pyright: ignore[reportCallIssue]
