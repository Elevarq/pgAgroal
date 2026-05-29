#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="/etc/pgexporter"
CONF_FILE="${CONF_DIR}/pgexporter.conf"
USERS_FILE="${CONF_DIR}/pgexporter_users.conf"

# ── Configuration from environment ────────────────────────────────────────────
export PG_BACKEND_HOST="${PG_BACKEND_HOST:-postgres}"
export PG_BACKEND_PORT="${PG_BACKEND_PORT:-5432}"
export PGEXPORTER_USER="${PGEXPORTER_USER:-pgexporter}"
export PGEXPORTER_METRICS_PORT="${PGEXPORTER_METRICS_PORT:-5002}"
export PGEXPORTER_LOG_LEVEL="${PGEXPORTER_LOG_LEVEL:-info}"

if [ -z "${PGEXPORTER_PASSWORD:-}" ]; then
    echo "FATAL: PGEXPORTER_PASSWORD is required (the monitoring user's password is never baked into the image)" >&2
    exit 1
fi

# ── Generate pgexporter.conf from template ────────────────────────────────────
envsubst < "${CONF_DIR}/pgexporter.conf.template" > "${CONF_FILE}"

# ── Master key (encrypts the users file); create once, idempotently ───────────
# pgexporter-admin requires a master key before any user can be added.
if [ ! -f "${HOME}/.pgexporter/master.key" ]; then
    printf '%s\n' "${PGEXPORTER_PASSWORD}" | pgexporter-admin master-key
fi

# ── Register the monitoring user (regenerated each start; idempotent) ─────────
# pgexporter-admin reads three lines from stdin: username, password, confirm.
rm -f "${USERS_FILE}"
printf '%s\n%s\n%s\n' "${PGEXPORTER_USER}" "${PGEXPORTER_PASSWORD}" "${PGEXPORTER_PASSWORD}" \
    | pgexporter-admin -f "${USERS_FILE}" user add

echo "Starting pgexporter: metrics :${PGEXPORTER_METRICS_PORT} -> ${PG_BACKEND_HOST}:${PG_BACKEND_PORT} as ${PGEXPORTER_USER}"

exec pgexporter -c "${CONF_FILE}" -u "${USERS_FILE}"
