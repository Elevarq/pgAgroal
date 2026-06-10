#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="${CONF_DIR:-/etc/pgagroal}"

# DEFAULT_HBA_SOURCE restricts accepted source addresses to the RFC1918
# private ranges. pgagroal's HBA matches CIDRs on OCTET boundaries only
# (e.g. /8, /16, /24 work; /12 does NOT), so 172.16.0.0/12 is expanded into
# the sixteen /16 blocks 172.16.0.0/16 .. 172.31.0.0/16. This covers the
# realistic deployment networks (Docker bridge 172.x, Kubernetes pod
# networks, on-prem subnets) without breaking them.
DEFAULT_HBA_SOURCE="10.0.0.0/8,172.16.0.0/16,172.17.0.0/16,172.18.0.0/16,172.19.0.0/16,172.20.0.0/16,172.21.0.0/16,172.22.0.0/16,172.23.0.0/16,172.24.0.0/16,172.25.0.0/16,172.26.0.0/16,172.27.0.0/16,172.28.0.0/16,172.29.0.0/16,172.30.0.0/16,172.31.0.0/16,192.168.0.0/16"

# build_hba_lines emits one pgagroal HBA `host` line per CIDR listed in
# PGAGROAL_HBA_SOURCE (comma-separated). The literal value `all` preserves
# the legacy any-source behaviour (explicit opt-out). The default restricts
# accepted source addresses to the RFC1918 private ranges, so a pooler that
# is accidentally exposed on a public interface rejects public-internet
# sources at the HBA layer. The backend PostgreSQL remains the authority for
# user authentication; this is defence in depth, not a replacement for it.
build_hba_lines() {
    local sources="${PGAGROAL_HBA_SOURCE:-${DEFAULT_HBA_SOURCE}}"
    local cidr
    local IFS=','
    for cidr in ${sources}; do
        # Trim surrounding whitespace.
        cidr="${cidr#"${cidr%%[![:space:]]*}"}"
        cidr="${cidr%"${cidr##*[![:space:]]}"}"
        [ -z "${cidr}" ] && continue
        printf 'host    all       all   %s   all\n' "${cidr}"
    done
}

main() {
    local conf_file="${CONF_DIR}/pgagroal.conf"
    local hba_file="${CONF_DIR}/pgagroal_hba.conf"

    # ── Generate pgagroal.conf from template ──────────────────────────────
    export PGAGROAL_HOST="${PGAGROAL_HOST:-*}"
    export PGAGROAL_PORT="${PGAGROAL_PORT:-6432}"
    export PGAGROAL_METRICS_PORT="${PGAGROAL_METRICS_PORT:-2346}"
    export PG_BACKEND_HOST="${PG_BACKEND_HOST:-postgres}"
    export PG_BACKEND_PORT="${PG_BACKEND_PORT:-5432}"
    export POOL_SIZE="${POOL_SIZE:-100}"
    export MAX_CONNECTIONS="${MAX_CONNECTIONS:-100}"
    export PGAGROAL_LOG_LEVEL="${PGAGROAL_LOG_LEVEL:-info}"
    # Transparent pooling passes unknown users through to the backend for
    # authentication. Set false to require every user be pre-registered with
    # pgagroal (frontend auth) — only do this if you register users.
    export PGAGROAL_ALLOW_UNKNOWN_USERS="${PGAGROAL_ALLOW_UNKNOWN_USERS:-true}"

    envsubst < "${CONF_DIR}/pgagroal.conf.template" > "${conf_file}"

    # ── Generate pgagroal_hba.conf from template ──────────────────────────
    # Expand PGAGROAL_HBA_SOURCE into host lines, then substitute only the
    # ${PGAGROAL_HBA_LINES} placeholder so CIDR values cannot accidentally
    # trigger further variable expansion.
    PGAGROAL_HBA_LINES="$(build_hba_lines)"
    export PGAGROAL_HBA_LINES
    # The single-quoted argument is envsubst's SHELL-FORMAT — the literal
    # name of the only variable to substitute — not a shell expansion.
    # shellcheck disable=SC2016
    envsubst '${PGAGROAL_HBA_LINES}' \
        < "${CONF_DIR}/pgagroal_hba.conf.template" > "${hba_file}"

    # ── Register pgagroal user if credentials supplied ────────────────────
    if [ -n "${PG_USERNAME:-}" ] && [ -n "${PG_PASSWORD:-}" ]; then
        local users_file="${CONF_DIR}/pgagroal_users.conf"
        # pgagroal-admin add-user reads from stdin: username\npassword\n
        printf '%s\n%s\n' "${PG_USERNAME}" "${PG_PASSWORD}" \
            | pgagroal-admin -f "${users_file}" -g user add-user \
            && echo "Registered user: ${PG_USERNAME}" \
            || echo "Warning: could not register user (allow_unknown_users=${PGAGROAL_ALLOW_UNKNOWN_USERS}, passthrough auth still works when true)"
    fi

    echo "Starting pgagroal on ${PGAGROAL_HOST}:${PGAGROAL_PORT} -> ${PG_BACKEND_HOST}:${PG_BACKEND_PORT}"

    # Upstream pgagroal does not remove its PID file on SIGKILL/OOM/crash,
    # so a stale /tmp/pgagroal.<port>.pid on the writable layer blocks the
    # next start. Safe because pgagroal is PID 1: if we are starting, no
    # prior pgagroal process can still be alive in this container.
    rm -f "/tmp/pgagroal.${PGAGROAL_PORT}.pid"

    # ── Start pgagroal in foreground ──────────────────────────────────────
    # pgagroal 2.0.x runs in foreground by default (no -d flag).
    # The -d flag means "daemon mode" and conflicts with log_type=console.
    exec pgagroal -c "${conf_file}" -a "${hba_file}"
}

# Run main only when executed, not when sourced (so tests can exercise
# build_hba_lines in isolation).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
