#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    echo "Missing .env. Copy .env.example to .env and fill in the required values." >&2
    exit 1
fi

# Check the file itself, even if the caller already exported these variables.
# Compose parses its own dotenv syntax, including quoted hashes containing $.
unset POSTGRES_PASSWORD JWT_SECRET AUTH_PASSWORD_HASHES_JSON
if ! docker compose --env-file .env -f docker-compose.yml config --quiet; then
    echo "Check .env: POSTGRES_PASSWORD, JWT_SECRET and AUTH_PASSWORD_HASHES_JSON are required." >&2
    exit 1
fi
echo ".env and Compose configuration OK."
