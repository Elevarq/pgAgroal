#!/usr/bin/env bash
#
# Integration test: pgagroal + pgexporter integration stack.
#
# Spec : specifications/compose-pgexporter-integration/spec.md
# Cases: AC-01 (stack up, ordered), AC-02 (pooled query + server metrics),
#        AC-03 (ordered startup), AC-06 (pgagroal native metrics).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
cd "${SCRIPT_DIR}"

COMPOSE="docker compose"
TIMEOUT=120
PGEXPORTER_METRICS_PORT="${PGEXPORTER_METRICS_PORT:-5002}"
PGAGROAL_METRICS_PORT="${PGAGROAL_METRICS_PORT:-2346}"

cleanup() {
    echo "--- Cleaning up ---"
    ${COMPOSE} down -v --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

wait_healthy() {
    local svc="$1" elapsed=0 cid
    cid="$(${COMPOSE} ps -q "${svc}")"
    if [ -z "${cid}" ]; then
        echo "FAIL: service '${svc}' is not defined / not started"
        exit 1
    fi
    until [ "$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cid}")" = "healthy" ]; do
        if [ "${elapsed}" -ge "${TIMEOUT}" ]; then
            echo "FAIL: ${svc} did not become healthy within ${TIMEOUT}s"
            ${COMPOSE} logs --tail=40 "${svc}"
            exit 1
        fi
        sleep 2; elapsed=$((elapsed + 2)); echo "  waiting for ${svc}... ${elapsed}s"
    done
    echo "  ${svc} healthy after ${elapsed}s"
}

echo "=== pgagroal + pgexporter Integration Test ==="

# --- AC-03: ordered startup is declared (depends_on health) ----------------
echo "--- AC-03: assert dependent services depend on postgres health ---"
config="$(${COMPOSE} config)"
for svc in pgagroal pgexporter; do
    if ! echo "${config}" | grep -A3 -E "^[[:space:]]+${svc}:" >/dev/null 2>&1; then
        echo "FAIL: service '${svc}' missing from compose config (AC-03)"
        exit 1
    fi
done
if ! echo "${config}" | grep -q "service_healthy"; then
    echo "FAIL: no 'service_healthy' dependency condition found (AC-03/R3)"
    exit 1
fi
echo "  ordered-startup dependency present"

# --- R1: pgexporter targets postgres directly, not pgagroal ----------------
# No service may set its backend host to pgagroal — the exporter must reach
# postgres directly so pooler statistics are not polluted by scrape traffic.
echo "--- R1: assert no service routes its backend through pgagroal ---"
if echo "${config}" | grep -iE "PG_BACKEND_HOST:[[:space:]]*[\"']?pgagroal"; then
    echo "FAIL: a service points PG_BACKEND_HOST at pgagroal; must target postgres directly (R1)"
    exit 1
fi
echo "  no service routes its backend through pgagroal"

echo "--- Step 1: Build and start full stack (fresh images) ---"
${COMPOSE} up -d --build postgres pgagroal pgexporter

# --- AC-01: all services reach healthy -------------------------------------
echo "--- AC-01: wait for postgres, pgagroal, pgexporter healthy ---"
wait_healthy postgres
wait_healthy pgagroal
wait_healthy pgexporter

# --- AC-02: pooled query through pgagroal ----------------------------------
echo "--- AC-02: pooled SELECT 1 via pgagroal:6432 ---"
${COMPOSE} run --rm -e PGPASSWORD=testpass test-client \
    psql -h pgagroal -p 6432 -U testuser -d testdb -c "SELECT 1 AS connection_ok;"

# Poll a /metrics endpoint until a series matching the pattern appears.
# pgexporter collects backend metrics on the first scrape, so a series may
# take a cycle to show up. Here-strings avoid SIGPIPE under pipefail.
wait_metric() {
    local url="$1" pattern="$2" timeout="${3:-60}" elapsed=0 body
    while :; do
        body="$(curl -fsS "${url}" 2>/dev/null || true)"
        if grep -qE "${pattern}" <<<"${body}"; then return 0; fi
        if [ "${elapsed}" -ge "${timeout}" ]; then
            echo "  no '${pattern}' within ${timeout}s; last body (head):"
            head -20 <<<"${body}"
            return 1
        fi
        sleep 2; elapsed=$((elapsed + 2))
    done
}

# --- AC-02: pgexporter server metrics --------------------------------------
echo "--- AC-02: pgexporter /metrics exposes PostgreSQL series ---"
if ! wait_metric "http://localhost:${PGEXPORTER_METRICS_PORT}/metrics" "^pgexporter_pg_" 60; then
    echo "FAIL: pgexporter /metrics contains no pgexporter_pg_* series (AC-02/B3)"
    exit 1
fi
echo "  pgexporter exposes PostgreSQL metrics"

# --- AC-06: pgagroal native metrics endpoint -------------------------------
echo "--- AC-06: pgagroal native /metrics exposes pooler series ---"
if ! wait_metric "http://localhost:${PGAGROAL_METRICS_PORT}/metrics" "^pgagroal_" 30; then
    echo "FAIL: pgagroal metrics endpoint contains no pgagroal_* series (AC-06/B7)"
    exit 1
fi
echo "  pgagroal exposes pooler metrics on :${PGAGROAL_METRICS_PORT}"

echo ""
echo "=== ALL INTEGRATION TESTS PASSED ==="
