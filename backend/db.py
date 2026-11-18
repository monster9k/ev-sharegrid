"""Database connection configuration shared by the backend routes."""

from __future__ import annotations

import os
from typing import Any


class DatabaseConfigurationError(RuntimeError):
    """Raised when the backend has no database credentials configured."""


def connect() -> Any:
    """Connect using DATABASE_URL or explicit POSTGRES_* environment variables."""
    database_url = os.getenv("DATABASE_URL", "").strip()
    if database_url:
        import psycopg2

        return psycopg2.connect(database_url)

    password = os.getenv("POSTGRES_PASSWORD")
    if not password:
        raise DatabaseConfigurationError(
            "Set DATABASE_URL or POSTGRES_PASSWORD before starting the backend"
        )

    import psycopg2

    return psycopg2.connect(
        dbname=os.getenv("POSTGRES_DB", "ev_sharegrid"),
        user=os.getenv("POSTGRES_USER", "postgres"),
        password=password,
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=int(os.getenv("POSTGRES_PORT", "5432")),
    )


def dict_cursor(connection: Any) -> Any:
    """Create a psycopg2 dictionary cursor without importing the driver at startup."""
    from psycopg2.extras import RealDictCursor

    return connection.cursor(cursor_factory=RealDictCursor)
