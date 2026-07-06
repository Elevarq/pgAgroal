#!/bin/bash
#
# Least-privilege monitoring role for pgexporter.
#
# pgexporter connects DIRECTLY to PostgreSQL (never through pgagroal) using a
# role granted pg_monitor, not a superuser. This models the recommended
# monitoring posture: the exporter can read the statistics views it needs and
# nothing more.
#
# The role password comes from the runtime environment (PGEXPORTER_PASSWORD,
# interpolated fail-fast by docker-compose.yml) — never a literal in this
# script (spec: no-static-credentials R4). psql's :'var' quoting keeps the
# value out of SQL parsing.
set -euo pipefail

psql -v ON_ERROR_STOP=1 \
     -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
     -v pgexporter_password="${PGEXPORTER_PASSWORD}" <<'EOSQL'
CREATE ROLE pgexporter WITH LOGIN PASSWORD :'pgexporter_password';
GRANT pg_monitor TO pgexporter;
EOSQL
