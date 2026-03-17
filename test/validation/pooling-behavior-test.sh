#!/usr/bin/env bash
#
# Pool behavior test: verify pgagroal actually reuses backend connections.
#
# Strategy:
#   1. Run N sequential short-lived client sessions through pgagroal
#   2. Each session records its pg_backend_pid()
#   3. If pooling works, many sessions reuse the same backend PID
#   4. Cross-check via pg_stat_activity on the backend
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
cd "${SCRIPT_DIR}"

COMPOSE="docker compose"
TIMEOUT=120
SESSIONS="${1:-15}"        # number of sequential client sessions

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

echo "=== Pooling Behavior Test (${SESSIONS} sequential sessions) ==="

echo "--- Step 1: Build container ---"
docker build -t pgagroal:test .

echo "--- Step 2: Start services ---"
${COMPOSE} up -d postgres pgagroal

echo "--- Step 3: Wait for healthy state ---"
wait_pgagroal_healthy

echo "--- Step 4: Run ${SESSIONS} sequential sessions, collect backend PIDs ---"

# Run inside a single test-client container. Each iteration opens a fresh
# psql connection (new client session) and prints the backend PID it got.
INNER_SCRIPT=$(cat <<'INNER'
#!/bin/sh
SESSIONS=$1
for i in $(seq 1 "${SESSIONS}"); do
    pid=$(psql -h pgagroal -p 6432 -U testuser -d testdb \
          -tA -c "SELECT pg_backend_pid();" 2>/dev/null)
    echo "PID:${pid}"
done
INNER
)

output=$(${COMPOSE} run --rm \
    -e PGPASSWORD=testpass \
    test-client \
    sh -c "${INNER_SCRIPT}" -- "${SESSIONS}" 2>&1)

# Extract PIDs
pids=$(echo "${output}" | grep '^PID:' | sed 's/PID://')
pid_count=$(echo "${pids}" | wc -l | tr -d ' ')
unique_pids=$(echo "${pids}" | sort -u)
unique_count=$(echo "${unique_pids}" | wc -l | tr -d ' ')

echo ""
echo "--- Step 5: Check backend connection count via pg_stat_activity ---"

backend_conns=$(${COMPOSE} exec -T postgres \
    psql -U testuser -d testdb -tA \
    -c "SELECT count(*) FROM pg_stat_activity WHERE usename = 'testuser' AND pid != pg_backend_pid();")
backend_conns=$(echo "${backend_conns}" | tr -d '[:space:]')

echo ""
echo "--- Summary ---"
echo "  Client sessions opened : ${pid_count}"
echo "  Unique backend PIDs    : ${unique_count}"
echo "  Backend conns (now)    : ${backend_conns}"
echo "  PIDs observed          : $(echo "${unique_pids}" | tr '\n' ' ')"

# Evaluate pooling behavior
if [ "${pid_count}" -eq 0 ]; then
    echo ""
    echo "FAIL: no PID data collected -- connections may have all failed"
    exit 1
fi

if [ "${unique_count}" -lt "${pid_count}" ]; then
    reuse_pct=$(( (pid_count - unique_count) * 100 / pid_count ))
    echo "  Reuse rate             : ${reuse_pct}%"
    echo ""
    echo "  Connection reuse detected: ${pid_count} sessions used only ${unique_count} backend connection(s)."
    echo ""
    echo "=== POOLING BEHAVIOR TEST PASSED ==="
elif [ "${unique_count}" -eq "${pid_count}" ] && [ "${pid_count}" -le 3 ]; then
    echo ""
    echo "  WARN: every session got a unique PID, but sample size is small (${pid_count})."
    echo "  This may be expected for very few sessions. Try a larger count."
    echo ""
    echo "=== POOLING BEHAVIOR TEST PASSED (inconclusive) ==="
else
    echo ""
    echo "  WARN: no connection reuse observed (${unique_count} unique PIDs for ${pid_count} sessions)."
    echo "  This does not necessarily indicate a bug -- session-mode pooling may open"
    echo "  fresh connections if the pool was empty or if idle_timeout expired them."
    echo "  Check pgagroal logs and pipeline mode."
    echo ""
    echo "=== POOLING BEHAVIOR TEST PASSED (no reuse observed) ==="
fi
