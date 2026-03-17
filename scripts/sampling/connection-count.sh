#!/usr/bin/env bash
#
# connection-count.sh — sample backend connection count at regular intervals.
#
# Lightweight: only counts connections. Use pg-stat-sampler.sh for detail.
#
# Usage:
#   scripts/sampling/connection-count.sh \
#     --host localhost --port 5432 --user postgres --db postgres \
#     --interval 2 --duration 120 --output /tmp/conn_count.csv
#
set -euo pipefail

HOST="localhost"
PORT="5432"
USER="postgres"
DB="postgres"
INTERVAL=2
DURATION=60
OUTPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)     shift; HOST="$1" ;;
        --port)     shift; PORT="$1" ;;
        --user)     shift; USER="$1" ;;
        --db)       shift; DB="$1" ;;
        --interval) shift; INTERVAL="$1" ;;
        --duration) shift; DURATION="$1" ;;
        --output)   shift; OUTPUT="$1" ;;
        --help)
            echo "Usage: $0 --host <h> --port <p> --user <u> --db <d> --interval <s> --duration <s> --output <file>"
            exit 0 ;;
        *) echo "Unknown: $1" >&2; exit 1 ;;
    esac
    shift
done

header="timestamp,total,active,idle"
if [ -n "${OUTPUT}" ]; then
    echo "${header}" > "${OUTPUT}"
else
    echo "${header}"
fi

elapsed=0
while [ "${elapsed}" -lt "${DURATION}" ]; do
    row=$(PGPASSWORD="${PGPASSWORD:-}" psql -h "${HOST}" -p "${PORT}" -U "${USER}" -d "${DB}" -tA -c "
        SELECT
            to_char(now(), 'HH24:MI:SS'),
            count(*),
            count(*) FILTER (WHERE state = 'active'),
            count(*) FILTER (WHERE state = 'idle')
        FROM pg_stat_activity
        WHERE backend_type = 'client backend'
          AND pid != pg_backend_pid()
    " 2>/dev/null | tr '|' ',')

    if [ -n "${OUTPUT}" ]; then
        echo "${row}" >> "${OUTPUT}"
    else
        echo "${row}"
    fi

    sleep "${INTERVAL}"
    elapsed=$((elapsed + INTERVAL))
done

if [ -n "${OUTPUT}" ]; then
    lines=$(wc -l < "${OUTPUT}" | tr -d ' ')
    echo "Wrote $((lines - 1)) samples to ${OUTPUT}"
fi
