#!/usr/bin/env bash
#
# Integration test: build, start, and verify pgagroal container.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
cd "${SCRIPT_DIR}"

# Ephemeral stack credentials (spec: no-static-credentials R5).
# shellcheck disable=SC1091
. test/lib/test-env.sh

COMPOSE="docker compose"
TIMEOUT=120   # seconds to wait for healthy services

cleanup() {
    echo "--- Cleaning up ---"
    ${COMPOSE} down -v --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Step 1: Build container ==="
docker build -t pgagroal:test .

echo "=== Step 2: Start services ==="
${COMPOSE} up -d postgres pgagroal

echo "=== Step 3: Wait for pgagroal to become healthy (max ${TIMEOUT}s) ==="
elapsed=0
until [ "$(docker inspect --format='{{.State.Health.Status}}' "$(${COMPOSE} ps -q pgagroal)")" = "healthy" ]; do
    if [ "${elapsed}" -ge "${TIMEOUT}" ]; then
        echo "FAIL: pgagroal did not become healthy within ${TIMEOUT}s"
        ${COMPOSE} logs pgagroal
        exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    echo "  waiting... ${elapsed}s"
done
echo "pgagroal is healthy after ${elapsed}s"

echo "=== Step 4: Test PostgreSQL connection through pgagroal ==="
${COMPOSE} run --rm -e PGPASSWORD="${POSTGRES_PASSWORD}" test-client \
    psql -h pgagroal -p 6432 -U testuser -d testdb -c "SELECT 1 AS connection_ok;"

echo ""
echo "=== ALL TESTS PASSED ==="
