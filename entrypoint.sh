#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="/etc/pgagroal"
CONF_FILE="${CONF_DIR}/pgagroal.conf"
HBA_FILE="${CONF_DIR}/pgagroal_hba.conf"

# ── Generate pgagroal.conf from template ──────────────────────────────────────

export PGAGROAL_HOST="${PGAGROAL_HOST:-*}"
export PGAGROAL_PORT="${PGAGROAL_PORT:-6432}"
export PGAGROAL_METRICS_PORT="${PGAGROAL_METRICS_PORT:-2346}"
export PG_BACKEND_HOST="${PG_BACKEND_HOST:-postgres}"
export PG_BACKEND_PORT="${PG_BACKEND_PORT:-5432}"
export POOL_SIZE="${POOL_SIZE:-100}"
export MAX_CONNECTIONS="${MAX_CONNECTIONS:-100}"
export PGAGROAL_LOG_LEVEL="${PGAGROAL_LOG_LEVEL:-info}"

envsubst < "${CONF_DIR}/pgagroal.conf.template" > "${CONF_FILE}"

# ── Generate pgagroal_hba.conf from template ──────────────────────────────────

envsubst < "${CONF_DIR}/pgagroal_hba.conf.template" > "${HBA_FILE}"

# ── Register pgagroal user if credentials supplied ────────────────────────────

if [ -n "${PG_USERNAME:-}" ] && [ -n "${PG_PASSWORD:-}" ]; then
    USERS_FILE="${CONF_DIR}/pgagroal_users.conf"
    # pgagroal-admin add-user reads from stdin: username\npassword\n
    printf '%s\n%s\n' "${PG_USERNAME}" "${PG_PASSWORD}" \
        | pgagroal-admin -f "${USERS_FILE}" -g user add-user \
        && echo "Registered user: ${PG_USERNAME}" \
        || echo "Warning: could not register user (allow_unknown_users=true, passthrough auth still works)"
fi

echo "Starting pgagroal on ${PGAGROAL_HOST}:${PGAGROAL_PORT} -> ${PG_BACKEND_HOST}:${PG_BACKEND_PORT}"

# Upstream pgagroal does not remove its PID file on SIGKILL/OOM/crash,
# so a stale /tmp/pgagroal.<port>.pid on the writable layer blocks the
# next start. Safe because pgagroal is PID 1: if we are starting, no
# prior pgagroal process can still be alive in this container.
rm -f "/tmp/pgagroal.${PGAGROAL_PORT}.pid"

# ── Start pgagroal in foreground ──────────────────────────────────────────────
# pgagroal 2.0.x runs in foreground by default (no -d flag).
# The -d flag means "daemon mode" and conflicts with log_type=console.

exec pgagroal -c "${CONF_FILE}" -a "${HBA_FILE}"
