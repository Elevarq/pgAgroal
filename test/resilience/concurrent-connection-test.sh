#!/usr/bin/env bash
#
# Resilience test: verify pgagroal handles concurrent connections under load.
#
# Sends a burst of parallel connections through the pooler and reports
# success/failure counts.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
cd "${SCRIPT_DIR}"

COMPOSE="docker compose"
TIMEOUT=120
CONCURRENCY="${1:-20}"      # number of parallel connections
QUERY_SLEEP="0.2"           # seconds each query holds the connection

cleanup() {
    echo "--- Cleaning up ---"
    ${COMPOSE} down -v --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

wait_pgagroal_healthy() {
    local elapsed=0
    until [ "$(docker inspect --format='{{.State.Health.Status}}' \
              "$(${COMPOSE} ps -q pgagroal)")" = "healthy" ]; do
        if [ "${elapsed}" -ge "${TIMEOUT}" ]; then
            echo "FAIL: pgagroal not healthy within ${TIMEOUT}s"
            ${COMPOSE} logs --tail=40 pgagroal
            exit 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "  pgagroal healthy after ${elapsed}s"
}

echo "=== Concurrent Connection Test (${CONCURRENCY} parallel) ==="

echo "--- Step 1: Build container ---"
docker build -t pgagroal:test .

echo "--- Step 2: Start services ---"
${COMPOSE} up -d postgres pgagroal

echo "--- Step 3: Wait for healthy state ---"
wait_pgagroal_healthy

echo "--- Step 4: Fire ${CONCURRENCY} concurrent connections ---"
# Run inside a single container to avoid spawning N containers.
# Each background psql holds the connection for QUERY_SLEEP seconds.
INNER_SCRIPT=$(cat <<'INNER'
#!/bin/sh
CONCURRENCY=$1
SLEEP=$2
RESULTS_DIR=$(mktemp -d)

run_one() {
    local id=$1
    if psql -h pgagroal -p 6432 -U testuser -d testdb \
         -c "SELECT pg_sleep(${SLEEP}), ${id} AS conn_id;" \
         -tA >/dev/null 2>&1; then
        touch "${RESULTS_DIR}/ok_${id}"
    else
        touch "${RESULTS_DIR}/fail_${id}"
    fi
}

for i in $(seq 1 "${CONCURRENCY}"); do
    run_one "$i" &
done
wait

ok_count=$(find "${RESULTS_DIR}" -name 'ok_*' | wc -l | tr -d ' ')
fail_count=$(find "${RESULTS_DIR}" -name 'fail_*' | wc -l | tr -d ' ')

echo "RESULTS: ok=${ok_count} fail=${fail_count} total=${CONCURRENCY}"
rm -rf "${RESULTS_DIR}"

if [ "${fail_count}" -gt 0 ]; then
    exit 1
fi
INNER
)

output=$(${COMPOSE} run --rm \
    -e PGPASSWORD=testpass \
    test-client \
    sh -c "${INNER_SCRIPT}" -- "${CONCURRENCY}" "${QUERY_SLEEP}" 2>&1)

echo "${output}"

# Parse results from last line
results_line=$(echo "${output}" | grep '^RESULTS:' || true)
if [ -z "${results_line}" ]; then
    echo "FAIL: could not parse test results"
    exit 1
fi

ok=$(echo "${results_line}" | sed 's/.*ok=\([0-9]*\).*/\1/')
fail=$(echo "${results_line}" | sed 's/.*fail=\([0-9]*\).*/\1/')

echo ""
echo "--- Summary ---"
echo "  Concurrency : ${CONCURRENCY}"
echo "  Succeeded   : ${ok}"
echo "  Failed      : ${fail}"

if [ "${fail}" -gt 0 ]; then
    echo ""
    echo "FAIL: ${fail} connections failed under concurrent load"
    exit 1
fi

echo ""
echo "=== CONCURRENT CONNECTION TEST PASSED ==="
