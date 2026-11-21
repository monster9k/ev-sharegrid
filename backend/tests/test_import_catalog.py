import pandas as pd
import pytest

from scripts import import_catalog


class FakeCursor:
    def __init__(self, fail_on=None):
        self.statements = []
        self.fail_on = fail_on
        self.closed = False

    def executemany(self, query, values):
        self.statements.append((" ".join(query.split()), values))

    def execute(self, query, params=None):
        normalized = " ".join(query.split())
        self.statements.append((normalized, params))
        if self.fail_on and self.fail_on in normalized:
            raise RuntimeError("forced catalog insert failure")

    def fetchone(self):
        email, = self.statements[-1][1]
        return {"admin@sharegrid.vn": (1, "ADMIN"), "host1@sharegrid.vn": (2, "HOST"),
                "user1@sharegrid.vn": (3, "USER")}[email]

    def close(self):
        self.closed = True


class FakeConnection:
    def __init__(self, cursor):
        self.fake_cursor = cursor
        self.commits = 0
        self.rollbacks = 0
        self.closed = False

    def cursor(self):
        return self.fake_cursor

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1

    def close(self):
        self.closed = True


def _empty_catalog_frames():
    model = pd.DataFrame([{
        "model_id": 2,
        "brand": "VinFast",
        "model_name": "VF 5 Plus",
        "vehicle_type": "CAR",
        "connector_type": "CCS2",
        "source_type": "REAL",
        "source_ref": "test",
        "battery_kwh": 37.23,
        "max_kw": 50.0,
        "max_ac_kw": 6.6,
        "max_dc_kw": 50.0,
        "standard_charger_kw": None,
        "data_note": "test fixture",
    }])
    return model, pd.DataFrame(), pd.DataFrame(), pd.DataFrame()


def test_demo_vehicle_is_inserted_after_its_model(monkeypatch):
    cursor = FakeCursor()
    connection = FakeConnection(cursor)
    monkeypatch.setattr(import_catalog.psycopg2, "connect", lambda **_kwargs: connection)

    import_catalog.seed_postgres_database(*_empty_catalog_frames())

    statements = [sql for sql, _params in cursor.statements]
    model_index = next(i for i, sql in enumerate(statements) if "INSERT INTO vehicle_model" in sql)
    demo_vehicle_index = next(i for i, sql in enumerate(statements) if "INSERT INTO vehicle (" in sql)
    assert model_index < demo_vehicle_index
    assert connection.commits == 1
    assert connection.rollbacks == 0


def test_upsert_loads_reference_coordinates_without_verifying_station(monkeypatch, tmp_path):
    monkeypatch.setattr(import_catalog, "DATA_DIR", str(tmp_path))
    models, stations, _, _ = import_catalog.clean_and_extract_catalogs()
    station = stations.loc[stations["station_id"] == 1]
    row = station.iloc[0]
    assert row["status"] == "PENDING"
    assert not row["verified"]
    lat, lng = row["lat"], row["lng"]
    assert pd.notna(lat) and pd.notna(lng)

    cursor = FakeCursor()
    connection = FakeConnection(cursor)
    monkeypatch.setattr(import_catalog.psycopg2, "connect", lambda **_kwargs: connection)
    import_catalog.seed_postgres_database(models, station, pd.DataFrame(), pd.DataFrame())

    sql, params = next(
        (sql, params) for sql, params in cursor.statements if sql.startswith("INSERT INTO charging_station")
    )
    values, conflict = sql.split("ON CONFLICT (station_id) DO UPDATE SET", 1)
    assert "ST_SetSRID(ST_MakePoint(%s, %s), 4326)" in values
    assert params[14:18] == (lat, lng, lng, lat)
    for column in ("lat", "lng", "location"):
        assert f"{column} = EXCLUDED.{column}" in conflict
    assert connection.commits == 1


def test_catalog_insert_failure_rolls_back_prints_real_error_and_exits(monkeypatch, capsys):
    cursor = FakeCursor(fail_on="INSERT INTO vehicle_model")
    connection = FakeConnection(cursor)
    monkeypatch.setattr(import_catalog.psycopg2, "connect", lambda **_kwargs: connection)

    with pytest.raises(SystemExit) as raised:
        import_catalog.seed_postgres_database(*_empty_catalog_frames())

    assert raised.value.code == 1
    assert "forced catalog insert failure" in capsys.readouterr().err
    assert connection.commits == 0
    assert connection.rollbacks == 1
    assert connection.closed and cursor.closed

def test_seed_preserves_existing_role_and_skips_incompatible_vehicle(monkeypatch):
    cursor = FakeCursor()
    fetchone = cursor.fetchone

    def existing_user():
        uid, role = fetchone()
        return (uid, "HOST") if role == "USER" else (uid, role)

    monkeypatch.setattr(cursor, "fetchone", existing_user)
    connection = FakeConnection(cursor)
    monkeypatch.setattr(import_catalog.psycopg2, "connect", lambda **_: connection)
    import_catalog.seed_postgres_database(*_empty_catalog_frames())
    account_writes = [sql for sql, _ in cursor.statements if sql.startswith("INSERT INTO app_user")]
    assert len(account_writes) == 3
    assert all("ON CONFLICT (email) DO NOTHING" in sql for sql in account_writes)
    assert not any("INSERT INTO vehicle (" in sql for sql, _ in cursor.statements)
    assert connection.commits == 1
