import pytest

from backend.db import DatabaseConfigurationError, connect


def test_database_credentials_are_required_without_database_url(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.delenv("POSTGRES_PASSWORD", raising=False)

    with pytest.raises(DatabaseConfigurationError, match="DATABASE_URL or POSTGRES_PASSWORD"):
        connect()
