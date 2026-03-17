#!/usr/bin/env bash
#
# pg-stat-sampler.sh — sample pg_stat_activity at regular intervals.
#
# Captures connection count, state, and query for each sample.
# Output is CSV suitable for spreadsheet analysis.
#
# Usage:
#   scripts/sampling/pg-stat-sampler.sh \
#     --host localhost --port 5432 --user postgres --db postgres \
#     --interval 5 --duration 120 --output /tmp/stat_activity.csv
#
set -euo pipefail

HOST="localhost"
PORT="5432"
USER="postgres"
DB="postgres"
INTERVAL=5
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

QUERY="COPY (
  SELECT
    now() AS sample_time,
    count(*) AS total_connections,
    count(*) FILTER (WHERE state = 'active') AS active,
    count(*) FILTER (WHERE state = 'idle') AS idle,
    count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_tx,
    count(*) FILTER (WHERE query LIKE 'SET %') AS set_commands,
    max(age(now(), backend_start)) AS oldest_connection
  FROM pg_stat_activity
  WHERE backend_type = 'client backend'
    AND usename != 'rdsadmin'
    AND pid != pg_backend_pid()
) TO STDOUT WITH CSV HEADER;"

elapsed=0
first=true

while [ "${elapsed}" -lt "${DURATION}" ]; do
    row=$(PGPASSWORD="${PGPASSWORD:-}" psql -h "${HOST}" -p "${PORT}" -U "${USER}" -d "${DB}" -tA -c "${QUERY}" 2>/dev/null)

    if [ "${first}" = true ]; then
        if [ -n "${OUTPUT}" ]; then
            echo "${row}" > "${OUTPUT}"
        else
            echo "${row}"
        fi
        first=false
    else
        # Skip header on subsequent samples
        data=$(echo "${row}" | tail -1)
        if [ -n "${OUTPUT}" ]; then
            echo "${data}" >> "${OUTPUT}"
        else
            echo "${data}"
        fi
    fi

    sleep "${INTERVAL}"
    elapsed=$((elapsed + INTERVAL))
done

if [ -n "${OUTPUT}" ]; then
    echo "Wrote $(wc -l < "${OUTPUT}" | tr -d ' ') samples to ${OUTPUT}"
fi
