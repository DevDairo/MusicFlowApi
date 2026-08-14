from __future__ import annotations

import pytest
from pydantic import SecretStr, ValidationError

from musicflow.core.config import Environment, Settings


def test_database_url_escapes_credentials(settings: Settings) -> None:
    settings_with_special_password = settings.model_copy(
        update={"db_password": SecretStr("p@ss:word/with?characters")}
    )

    rendered = settings_with_special_password.database_url.render_as_string(hide_password=False)

    assert "p%40ss%3Aword%2Fwith%3Fcharacters" in rendered
    assert "postgresql+asyncpg" in rendered


def test_production_rejects_placeholder_password() -> None:
    with pytest.raises(ValidationError):
        Settings(
            service_name="api",
            environment=Environment.PRODUCTION,
            db_host="postgres",
            db_name="musicflow",
            db_user="musicflow",
            db_password=SecretStr("replace-with-a-password"),
            oidc_issuer="https://identity.example/realms/musicflow",
            oidc_audience="musicflow-api",
            oidc_jwks_url=(
                "http://keycloak-gateway:8080/realms/musicflow/protocol/openid-connect/certs"
            ),
        )


def test_production_rejects_non_https_oidc_issuer() -> None:
    with pytest.raises(ValidationError):
        Settings(
            service_name="api",
            environment=Environment.PRODUCTION,
            db_host="postgres",
            db_name="musicflow",
            db_user="musicflow",
            db_password=SecretStr("a-strong-production-password-123456"),
            oidc_issuer="http://identity.example/realms/musicflow",
            oidc_audience="musicflow-api",
            oidc_jwks_url=(
                "http://keycloak-gateway:8080/realms/musicflow/protocol/openid-connect/certs"
            ),
        )


def test_oidc_jwks_url_can_use_the_private_identity_network(settings: Settings) -> None:
    assert settings.oidc_issuer == "https://identity.test/realms/musicflow"
    assert settings.oidc_jwks_url == (
        "http://keycloak-gateway:8080/realms/musicflow/protocol/openid-connect/certs"
    )
