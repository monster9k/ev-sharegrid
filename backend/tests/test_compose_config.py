from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]


def test_compose_backend_has_required_ai_auth_and_seed_dependencies():
    compose = yaml.safe_load((ROOT / "docker-compose.yml").read_text(encoding="utf-8"))
    backend = compose["services"]["backend"]

    assert backend["environment"]["AI_URL"] == "${AI_URL:-http://ai-engine:8001}"
    assert backend["environment"]["JWT_SECRET"] == "${JWT_SECRET:?Set JWT_SECRET in .env}"
    assert backend["environment"]["AUTH_PASSWORD_HASHES_JSON"] == (
        "${AUTH_PASSWORD_HASHES_JSON:?Set AUTH_PASSWORD_HASHES_JSON in .env}"
    )
    assert backend["depends_on"]["catalog-seed"]["condition"] == "service_completed_successfully"
    assert backend["depends_on"]["ai-engine"]["condition"] == "service_started"


def test_env_example_documents_compose_auth_values_without_secrets():
    example = (ROOT / ".env.example").read_text(encoding="utf-8")

    assert "AI_URL=http://ai-engine:8001" in example
    assert "JWT_SECRET=" in example
    assert "AUTH_PASSWORD_HASHES_JSON=" in example
    assert "secrets.token_urlsafe(48)" in example
    assert "hash_password" in example
