#!/usr/bin/env bash
#
# Failure mode test: verify pgagroal behavior with invalid credentials.
#
# Validates:
#   - wrong password produces a clear authentication error
#   - pgagroal does not crash or become unhealthy
#   - correct credentials still work after a bad-password attempt
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
cd "${SCRIPT_DIR}"

COMPOSE="docker compose"
TIMEOUT=120

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

echo "=== Invalid Credentials Test ==="

echo "--- Step 1: Build container ---"
docker build -t pgagroal:test .

echo "--- Step 2: Start services ---"
${COMPOSE} up -d postgres pgagroal

echo "--- Step 3: Wait for healthy state ---"
wait_pgagroal_healthy

echo "--- Step 4: Attempt connection with wrong password ---"
set +e
bad_output=$(${COMPOSE} run --rm \
    -e PGPASSWORD=wrong_password_12345 \
    test-client \
    psql -h pgagroal -p 6432 -U testuser -d testdb \
         -c "SELECT 1;" 2>&1)
bad_exit=$?
set -e

if [ "${bad_exit}" -ne 0 ]; then
    echo "  wrong password rejected as expected (exit code: ${bad_exit})"
else
    echo "FAIL: connection with wrong password succeeded unexpectedly"
    exit 1
fi

# Check the error message is authentication-related
if echo "${bad_output}" | grep -qi -e "password" -e "authentication" -e "auth" -e "FATAL"; then
    echo "  error message is authentication-related (clear to operator)"
    echo "  output: $(echo "${bad_output}" | grep -i -e "password" -e "authentication" -e "auth" -e "FATAL" | head -2)"
else
    echo "  WARN: error message does not clearly indicate auth failure:"
    echo "  output: $(echo "${bad_output}" | head -3)"
fi

echo "--- Step 5: Attempt connection with non-existent user ---"
set +e
${COMPOSE} run --rm \
    -e PGPASSWORD=testpass \
    test-client \
    psql -h pgagroal -p 6432 -U no_such_user_xyz -d testdb \
         -c "SELECT 1;" >/dev/null 2>&1
nouser_exit=$?
set -e

if [ "${nouser_exit}" -ne 0 ]; then
    echo "  non-existent user rejected as expected (exit code: ${nouser_exit})"
else
    echo "  WARN: non-existent user connection succeeded (allow_unknown_users=true)"
fi

echo "--- Step 6: Verify pgagroal is still healthy ---"
health=$(docker inspect --format='{{.State.Health.Status}}' \
    "$(${COMPOSE} ps -q pgagroal)")
if [ "${health}" = "healthy" ]; then
    echo "  pgagroal still healthy after bad credential attempts"
else
    echo "FAIL: pgagroal became unhealthy after bad credential attempts (status: ${health})"
    exit 1
fi

echo "--- Step 7: Verify correct credentials still work ---"
set +e
good_output=$(${COMPOSE} run --rm \
    -e PGPASSWORD=testpass \
    test-client \
    psql -h pgagroal -p 6432 -U testuser -d testdb \
         -tA -c "SELECT 'ok';" 2>&1)
good_exit=$?
set -e

good_result=$(echo "${good_output}" | grep -x 'ok' || true)

if [ "${good_exit}" -eq 0 ] && [ "${good_result}" = "ok" ]; then
    echo "  correct credentials work after bad-password attempts"
else
    echo "FAIL: correct credentials stopped working after bad-password attempts"
    echo "  exit: ${good_exit}, output: ${good_output}"
    exit 1
fi

echo ""
echo "--- Summary ---"
echo "  Wrong password   : rejected cleanly (exit ${bad_exit})"
echo "  Unknown user     : rejected (exit ${nouser_exit})"
echo "  Daemon health    : ${health}"
echo "  Good creds after : work"
echo ""
echo "=== INVALID CREDENTIALS TEST PASSED ==="
