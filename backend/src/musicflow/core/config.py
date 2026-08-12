from __future__ import annotations

from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Literal, Self

from pydantic import Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import URL

MIN_PRODUCTION_PASSWORD_LENGTH = 16
DEFAULT_WORKER_HEALTH_FILE = Path("/run/musicflow/worker-heartbeat")


class Environment(StrEnum):
    DEVELOPMENT = "development"
    TEST = "test"
    PRODUCTION = "production"


class Settings(BaseSettings):
    """Runtime configuration loaded exclusively from MUSICFLOW_* variables."""

    model_config = SettingsConfigDict(
        env_prefix="MUSICFLOW_",
        case_sensitive=False,
        extra="ignore",
        env_file=None,
    )

    service_name: str = Field(min_length=1, max_length=50)
    environment: Environment = Environment.DEVELOPMENT
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"

    db_host: str = Field(min_length=1, max_length=253)
    db_port: int = Field(default=5432, ge=1, le=65535)
    db_name: str = Field(min_length=1, max_length=63)
    db_user: str = Field(min_length=1, max_length=63)
    db_password: SecretStr
    db_connect_timeout_seconds: float = Field(default=3.0, gt=0, le=30)

    worker_heartbeat_seconds: float = Field(default=5.0, ge=1, le=60)
    worker_health_file: Path = DEFAULT_WORKER_HEALTH_FILE

    @model_validator(mode="after")
    def reject_placeholder_production_secret(self) -> Self:
        password = self.db_password.get_secret_value()
        if self.environment is Environment.PRODUCTION and (
            password.startswith("replace-with-") or len(password) < MIN_PRODUCTION_PASSWORD_LENGTH
        ):
            raise ValueError("A strong database password is required in production.")
        return self

    @property
    def database_url(self) -> URL:
        """Build a safely escaped SQLAlchemy URL without string interpolation."""

        return URL.create(
            drivername="postgresql+asyncpg",
            username=self.db_user,
            password=self.db_password.get_secret_value(),
            host=self.db_host,
            port=self.db_port,
            database=self.db_name,
        )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()  # pyright: ignore[reportCallIssue]
