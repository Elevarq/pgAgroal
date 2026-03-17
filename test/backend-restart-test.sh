#!/usr/bin/env bash
#
# Resilience test: verify pgagroal recovers after a PostgreSQL backend restart.
#
# Exit codes:
#   0  pgagroal recovered and accepted connections after backend restart
#   1  pgagroal did not recover within the timeout
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

COMPOSE="docker compose"
TIMEOUT=120
RECOVERY_TIMEOUT=60

cleanup() {
    echo "--- Cleaning up ---"
    ${COMPOSE} down -v --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

# ── helpers ───────────────────────────────────────────────────────────────────

wait_pgagroal_healthy() {
    local label="$1"
    local limit="$2"
    local elapsed=0

    echo "  waiting for pgagroal healthy (${label}, max ${limit}s)..."
    until [ "$(docker inspect --format='{{.State.Health.Status}}' \
              "$(${COMPOSE} ps -q pgagroal)")" = "healthy" ]; do
        if [ "${elapsed}" -ge "${limit}" ]; then
            echo "FAIL: pgagroal not healthy within ${limit}s (${label})"
            ${COMPOSE} logs --tail=40 pgagroal
            return 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "  pgagroal healthy after ${elapsed}s (${label})"
}

run_query() {
    ${COMPOSE} run --rm -e PGPASSWORD=testpass test-client \
        psql -h pgagroal -p 6432 -U testuser -d testdb \
             -c "SELECT 'ok' AS status;" -tA 2>/dev/null
}

# ── test steps ────────────────────────────────────────────────────────────────

echo "=== Backend Restart Resilience Test ==="

echo "--- Step 1: Build container ---"
docker build -t pgagroal:test .

echo "--- Step 2: Start services ---"
${COMPOSE} up -d postgres pgagroal

echo "--- Step 3: Wait for initial healthy state ---"
wait_pgagroal_healthy "initial" "${TIMEOUT}"

echo "--- Step 4: Verify baseline connection ---"
result=$(run_query)
if [ "${result}" != "ok" ]; then
    echo "FAIL: baseline query returned '${result}' instead of 'ok'"
    exit 1
fi
echo "  baseline connection OK"

echo "--- Step 5: Restart PostgreSQL backend ---"
${COMPOSE} restart postgres
echo "  postgres container restarted"

echo "--- Step 6: Wait for PostgreSQL to be ready ---"
elapsed=0
until ${COMPOSE} exec -T postgres pg_isready -U testuser -d testdb >/dev/null 2>&1; do
    if [ "${elapsed}" -ge "${RECOVERY_TIMEOUT}" ]; then
        echo "FAIL: postgres did not become ready within ${RECOVERY_TIMEOUT}s"
        exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done
echo "  postgres ready after ${elapsed}s"

echo "--- Step 7: Verify pgagroal recovers and accepts connections ---"
elapsed=0
recovered=false
while [ "${elapsed}" -lt "${RECOVERY_TIMEOUT}" ]; do
    if result=$(run_query) && [ "${result}" = "ok" ]; then
        recovered=true
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    echo "  retrying... ${elapsed}s"
done

if [ "${recovered}" = true ]; then
    echo "  pgagroal recovered after ${elapsed}s"
else
    echo "FAIL: pgagroal did not recover within ${RECOVERY_TIMEOUT}s after backend restart"
    ${COMPOSE} logs --tail=40 pgagroal
    exit 1
fi

echo ""
echo "=== BACKEND RESTART TEST PASSED ==="
