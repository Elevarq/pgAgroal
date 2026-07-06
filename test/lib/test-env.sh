#!/usr/bin/env bash
#
# Ephemeral stack credentials for tests and CI.
#
# Spec : specifications/no-static-credentials/spec.md (B4, R5)
#
# Source this before any docker compose invocation. Generates a random
# credential per variable unless the caller already exported one (so a
# failing run can be reproduced with fixed values). Never commit real
# values; docker-compose.yml interpolates these fail-fast.

gen_test_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 16
    else
        head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(gen_test_secret)}"
PGEXPORTER_PASSWORD="${PGEXPORTER_PASSWORD:-$(gen_test_secret)}"
export POSTGRES_PASSWORD PGEXPORTER_PASSWORD
