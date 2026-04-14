#!/usr/bin/env bash
#
# Resilience test: verify the pgagroal container survives restart after
# an ungraceful termination (SIGKILL / OOM / stop-grace expiry).
#
# Upstream pgagroal removes its PID file on SIGTERM but not on SIGKILL.
# Because the image keeps the PID file on the writable layer
# (/tmp/pgagroal.<port>.pid), a stale file survives and blocks the next
# start with:
#   pgagroal: PID file </tmp//pgagroal.<port>.pid> exists, is there
#             another instance running ?
# The entrypoint removes any stale PID file before exec'ing pgagroal.
#
# Spec:  specifications/docker-restart-resilience/spec.md
# Cases: AC-01, AC-02, AC-03
#
# Exit codes:
#   0  container restarts cleanly and recovers to healthy
#   1  restart failed (container unhealthy, query failed, or unclean stop)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
cd "${SCRIPT_DIR}"

IMAGE="pgagroal:test"
NET="pgagroal-restart-net"
PG="pgagroal-restart-pg"
POOLER="pgagroal-restart-pool"
PGAGROAL_PORT="6432"
HEALTHY_TIMEOUT=60
DBG_IMAGE="pgagroal-restart-dbg:stopped"

cleanup() {
    echo "--- Cleaning up ---"
    docker rm -f "${POOLER}" "${PG}" 2>/dev/null || true
    docker network rm "${NET}" 2>/dev/null || true
    docker rmi "${DBG_IMAGE}" 2>/dev/null || true
}
trap cleanup EXIT

wait_healthy() {
    local name="$1"
    local limit="$2"
    local elapsed=0
    echo "  waiting for ${name} healthy (max ${limit}s)..."
    until [ "$(docker inspect --format='{{.State.Health.Status}}' "${name}" 2>/dev/null || echo none)" = "healthy" ]; do
        if [ "${elapsed}" -ge "${limit}" ]; then
            echo "FAIL: ${name} not healthy within ${limit}s"
            docker logs --tail=60 "${name}" || true
            return 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "  ${name} healthy after ${elapsed}s"
}

run_query() {
    docker run --rm --network "${NET}" \
        -e PGPASSWORD=testpass \
        postgres:17.4-bookworm \
        psql -h "${POOLER}" -p "${PGAGROAL_PORT}" \
             -U testuser -d testdb -tA \
             -c "SELECT 'ok' AS status;" 2>/dev/null
}

echo "=== Docker Restart Resilience Test ==="

echo "--- Step 1: Build image ---"
docker build -t "${IMAGE}" .

echo "--- Step 2: Create network ---"
docker network create "${NET}" >/dev/null

echo "--- Step 3: Start postgres ---"
docker run -d --name "${PG}" --network "${NET}" \
    -e POSTGRES_USER=testuser \
    -e POSTGRES_PASSWORD=testpass \
    -e POSTGRES_DB=testdb \
    postgres:17.4-bookworm >/dev/null

elapsed=0
until docker exec "${PG}" pg_isready -U testuser -d testdb >/dev/null 2>&1; do
    if [ "${elapsed}" -ge 60 ]; then
        echo "FAIL: postgres did not become ready"
        exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done
echo "  postgres ready"

echo "--- Step 4: Start pgagroal (first run) — AC-01 ---"
docker run -d --name "${POOLER}" --network "${NET}" \
    -e PG_BACKEND_HOST="${PG}" \
    -e PG_BACKEND_PORT=5432 \
    -e PGAGROAL_PORT="${PGAGROAL_PORT}" \
    "${IMAGE}" >/dev/null

wait_healthy "${POOLER}" "${HEALTHY_TIMEOUT}"

if ! docker exec "${POOLER}" test -f "/tmp/pgagroal.${PGAGROAL_PORT}.pid"; then
    echo "FAIL: expected /tmp/pgagroal.${PGAGROAL_PORT}.pid to exist on running container"
    exit 1
fi
echo "  PID file present"

result=$(run_query)
if [ "${result}" != "ok" ]; then
    echo "FAIL: baseline query returned '${result}' instead of 'ok'"
    exit 1
fi
echo "  baseline query OK"

echo "--- Step 5: SIGKILL (simulates stop-grace expiry / OOM / crash) ---"
docker kill --signal=SIGKILL "${POOLER}" >/dev/null
# Wait briefly for the docker engine to settle into 'exited'.
for _ in 1 2 3 4 5; do
    status=$(docker inspect --format='{{.State.Status}}' "${POOLER}" 2>/dev/null || echo none)
    [ "${status}" = "exited" ] && break
    sleep 1
done
echo "  container exited"

echo "--- Step 6: Confirm stale PID file survives on writable layer ---"
docker commit "${POOLER}" "${DBG_IMAGE}" >/dev/null
if ! docker run --rm --entrypoint test "${DBG_IMAGE}" -f "/tmp/pgagroal.${PGAGROAL_PORT}.pid"; then
    echo "FAIL: expected stale PID file on writable layer — cannot exercise the bug"
    exit 1
fi
echo "  stale PID file confirmed on writable layer"

echo "--- Step 7: docker start — AC-02 (the regression) ---"
docker start "${POOLER}" >/dev/null
if ! wait_healthy "${POOLER}" "${HEALTHY_TIMEOUT}"; then
    echo "FAIL: container did not recover after SIGKILL+start (stale PID blocked startup)"
    exit 1
fi

if docker logs "${POOLER}" 2>&1 | grep -q "PID file .* exists, is there another instance running"; then
    echo "FAIL: pgagroal reported stale PID file conflict after restart"
    docker logs --tail=40 "${POOLER}"
    exit 1
fi

result=$(run_query)
if [ "${result}" != "ok" ]; then
    echo "FAIL: post-restart query returned '${result}' instead of 'ok'"
    docker logs --tail=40 "${POOLER}"
    exit 1
fi
echo "  post-restart query OK"

echo "--- Step 8: Graceful SIGTERM + start — AC-03 ---"
start_ts=$(date +%s)
docker stop --timeout 10 "${POOLER}" >/dev/null
stop_ts=$(date +%s)
elapsed=$((stop_ts - start_ts))
exit_code=$(docker inspect --format='{{.State.ExitCode}}' "${POOLER}")
if [ "${exit_code}" != "0" ]; then
    echo "FAIL: graceful stop produced exit ${exit_code} (expected 0)"
    exit 1
fi
if [ "${elapsed}" -ge 10 ]; then
    echo "FAIL: graceful stop took ${elapsed}s (>= 10s grace — likely SIGKILLed)"
    exit 1
fi
echo "  clean SIGTERM shutdown (exit 0, ${elapsed}s)"

docker start "${POOLER}" >/dev/null
wait_healthy "${POOLER}" "${HEALTHY_TIMEOUT}"
result=$(run_query)
if [ "${result}" != "ok" ]; then
    echo "FAIL: query after graceful-restart returned '${result}'"
    exit 1
fi
echo "  graceful-restart query OK"

echo ""
echo "=== DOCKER RESTART TEST PASSED ==="
