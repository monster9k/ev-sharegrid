from fastapi.testclient import TestClient

from backend.main import app


client = TestClient(app)


def test_cors_allows_deployed_web_origin():
    response = client.get("/", headers={"Origin": "https://ev-sharegrid.web.app"})

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "https://ev-sharegrid.web.app"


def test_cors_allows_localhost_on_any_port():
    response = client.options(
        "/api/v1/requests",
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:5173"


def test_cors_rejects_lookalike_hostname():
    response = client.get("/", headers={"Origin": "http://localhost.attacker.example"})

    assert response.status_code == 200
    assert "access-control-allow-origin" not in response.headers
