from __future__ import annotations

from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Literal, Self
from urllib.parse import urlsplit

from pydantic import Field, SecretStr, field_validator, model_validator
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

    oidc_issuer: str = Field(min_length=1, max_length=512)
    oidc_audience: str = Field(min_length=1, max_length=255)
    oidc_jwks_url: str = Field(min_length=1, max_length=512)
    oidc_jwks_cache_seconds: int = Field(default=300, ge=30, le=3600)
    oidc_clock_skew_seconds: int = Field(default=30, ge=0, le=120)

    rate_limit_enabled: bool = True
    rate_limit_window_seconds: int = Field(default=60, ge=1, le=3600)
    rate_limit_origin_requests: int = Field(default=120, ge=1, le=10_000)
    rate_limit_identity_requests: int = Field(default=60, ge=1, le=10_000)
    rate_limit_max_keys: int = Field(default=10_000, ge=100, le=100_000)
    trust_cloudflare_connecting_ip: bool = False

    worker_heartbeat_seconds: float = Field(default=5.0, ge=1, le=60)
    worker_health_file: Path = DEFAULT_WORKER_HEALTH_FILE

    @field_validator("oidc_issuer")
    @classmethod
    def validate_oidc_issuer(cls, value: str) -> str:
        parsed = urlsplit(value)
        if (
            parsed.scheme not in {"http", "https"}
            or not parsed.hostname
            or parsed.username
            or parsed.password
            or parsed.query
            or parsed.fragment
            or value.endswith("/")
        ):
            raise ValueError("OIDC issuer must be an absolute URL without credentials or suffixes.")
        return value

    @field_validator("oidc_jwks_url")
    @classmethod
    def validate_oidc_jwks_url(cls, value: str) -> str:
        parsed = urlsplit(value)
        if (
            parsed.scheme not in {"http", "https"}
            or not parsed.hostname
            or parsed.username
            or parsed.password
            or parsed.query
            or parsed.fragment
            or not parsed.path.endswith("/protocol/openid-connect/certs")
        ):
            raise ValueError("OIDC JWKS URL must be an absolute Keycloak certs endpoint.")
        return value

    @model_validator(mode="after")
    def reject_placeholder_production_secret(self) -> Self:
        password = self.db_password.get_secret_value()
        if self.environment is Environment.PRODUCTION and (
            password.startswith("replace-with-") or len(password) < MIN_PRODUCTION_PASSWORD_LENGTH
        ):
            raise ValueError("A strong database password is required in production.")
        insecure_production_issuer = (
            self.environment is Environment.PRODUCTION
            and urlsplit(self.oidc_issuer).scheme != "https"
        )
        if insecure_production_issuer:
            raise ValueError("An HTTPS OIDC issuer is required in production.")
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
