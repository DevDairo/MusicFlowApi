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
        )
