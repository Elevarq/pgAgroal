#!/usr/bin/env bash
#
# Validation test: pgexporter pointed at an unreachable backend is
# surfaced, not silently treated as healthy.
#
# Spec : specifications/compose-pgexporter-integration/spec.md
# Case : AC-04 (B5, failure condition: unreachable backend)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
cd "${SCRIPT_DIR}"

COMPOSE="docker compose"
SETTLE=30
PGEXPORTER_METRICS_PORT="${PGEXPORTER_METRICS_PORT:-5002}"

cleanup() {
    echo "--- Cleaning up ---"
    ${COMPOSE} -f docker-compose.yml -f /tmp/pgexporter-badbackend.yml down -v --remove-orphans 2>/dev/null || true
    rm -f /tmp/pgexporter-badbackend.yml
}
trap cleanup EXIT

echo "=== pgexporter Unreachable-Backend Test (AC-04) ==="

# Override the pgexporter backend host to an unresolvable name.
cat > /tmp/pgexporter-badbackend.yml <<'YML'
services:
  pgexporter:
    environment:
      PG_BACKEND_HOST: no-such-backend-host
YML

echo "--- Step 1: Start stack with broken pgexporter backend (fresh images) ---"
${COMPOSE} -f docker-compose.yml -f /tmp/pgexporter-badbackend.yml up -d --build postgres pgexporter

echo "--- Step 3: Let it settle (${SETTLE}s) ---"
sleep "${SETTLE}"

cid="$(${COMPOSE} ps -q pgexporter)"
if [ -z "${cid}" ]; then
    echo "FAIL: pgexporter service not defined (AC-04 presupposes the service exists)"
    exit 1
fi

# The failure must be observable: EITHER pgexporter is not healthy,
# OR /metrics omits PostgreSQL series. A fully-healthy + pg_* present
# state would be a silent false pass.
health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cid}")"
echo "  pgexporter health: ${health}"

pg_series_present=no
if metrics="$(curl -fsS "http://localhost:${PGEXPORTER_METRICS_PORT}/metrics" 2>/dev/null)"; then
    if echo "${metrics}" | grep -qE "^pgexporter_pg_"; then
        pg_series_present=yes
    fi
fi
echo "  pg_* series present: ${pg_series_present}"

if [ "${health}" = "healthy" ] && [ "${pg_series_present}" = "yes" ]; then
    echo "FAIL: unreachable backend was hidden — pgexporter healthy AND pg_* metrics present (AC-04/B5)"
    exit 1
fi

echo "  unreachable backend is surfaced (no silent pass)"
echo ""
echo "=== UNREACHABLE-BACKEND TEST PASSED ==="
