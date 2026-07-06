#!/usr/bin/env bash
#
# Resilience test: backend loss after startup degrades cleanly.
#
# Spec : specifications/compose-pgexporter-integration/spec.md
# Case : AC-05 (B6, I4)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
cd "${SCRIPT_DIR}"

# Ephemeral stack credentials (spec: no-static-credentials R5).
. test/lib/test-env.sh

COMPOSE="docker compose"
TIMEOUT=120
PGEXPORTER_METRICS_PORT="${PGEXPORTER_METRICS_PORT:-5002}"

cleanup() {
    echo "--- Cleaning up ---"
    ${COMPOSE} down -v --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

wait_healthy() {
    local svc="$1" elapsed=0 cid
    cid="$(${COMPOSE} ps -q "${svc}")"
    [ -n "${cid}" ] || { echo "FAIL: service '${svc}' not started"; exit 1; }
    until [ "$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cid}")" = "healthy" ]; do
        if [ "${elapsed}" -ge "${TIMEOUT}" ]; then
            echo "FAIL: ${svc} not healthy within ${TIMEOUT}s"; ${COMPOSE} logs --tail=40 "${svc}"; exit 1
        fi
        sleep 2; elapsed=$((elapsed + 2))
    done
    echo "  ${svc} healthy after ${elapsed}s"
}

echo "=== Backend-Loss Resilience Test (AC-05) ==="

echo "--- Step 1: Build and start full stack (fresh images) ---"
${COMPOSE} up -d --build postgres pgagroal pgexporter
wait_healthy postgres
wait_healthy pgagroal
wait_healthy pgexporter

echo "--- Step 3: Stop the backend ---"
${COMPOSE} stop postgres

echo "--- Step 4: pgagroal connection fails within blocking_timeout (no hang) ---"
# blocking_timeout in the template is 30s; allow margin. The timeout runs
# INSIDE the (Linux) test-client container so the test does not depend on a
# host `timeout` binary (absent on macOS), which would otherwise mask the
# real result with exit 127.
start=$(date +%s)
set +e
# --no-deps is essential: without it, `compose run` would restart postgres to
# satisfy the dependency chain, defeating the backend-loss scenario.
${COMPOSE} run --rm --no-deps -e PGPASSWORD="${POSTGRES_PASSWORD}" test-client \
    sh -c "timeout 60 psql -h pgagroal -p 6432 -U testuser -d testdb -c 'SELECT 1;'" >/dev/null 2>&1
q_exit=$?
set -e
end=$(date +%s)
elapsed=$((end - start))
if [ "${q_exit}" -eq 124 ]; then
    echo "FAIL: pgagroal query hung past 60s after backend loss (AC-05/B6)"
    exit 1
fi
if [ "${q_exit}" -eq 0 ]; then
    echo "FAIL: query succeeded with backend down — unexpected (AC-05/B6)"
    exit 1
fi
echo "  pgagroal failed cleanly in ${elapsed}s (exit ${q_exit})"

echo "--- Step 5: pgexporter HTTP endpoint still responds ---"
if ! curl -fsS "http://localhost:${PGEXPORTER_METRICS_PORT}/metrics" >/dev/null 2>&1; then
    echo "FAIL: pgexporter endpoint stopped responding after backend loss (AC-05/B6)"
    exit 1
fi
echo "  pgexporter endpoint still up with backend down"

echo ""
echo "=== BACKEND-LOSS RESILIENCE TEST PASSED ==="
