#!/usr/bin/env bash
#
# Validation test: HBA source-address restriction (#48).
#
# Dockerless — sources the entrypoint and exercises build_hba_lines plus the
# envsubst rendering of the HBA and conf templates. Verifies the acceptance
# cases in specifications/hba-source-restriction/acceptance-cases.md.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
cd "${REPO_ROOT}"

# shellcheck source=/dev/null
source ./entrypoint.sh

pass=0
fail=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "${expected}" = "${actual}" ]; then
        echo "  PASS: ${desc}"
        pass=$((pass + 1))
    else
        echo "  FAIL: ${desc}"
        echo "        expected: ${expected}"
        echo "        actual:   ${actual}"
        fail=$((fail + 1))
    fi
}

echo "=== HBA Source Restriction Test ==="

# AC-01: default restricts to RFC1918 (octet-aligned), never `all`.
unset PGAGROAL_HBA_SOURCE
out="$(build_hba_lines)"
check "AC-01 default line count (18 RFC1918 octet-aligned)" "18" "$(printf '%s\n' "${out}" | grep -c '^host')"
check "AC-01 contains 10.0.0.0/8"        "1"  "$(printf '%s\n' "${out}" | grep -c '10\.0\.0\.0/8')"
check "AC-01 contains 172.16.0.0/16"     "1"  "$(printf '%s\n' "${out}" | grep -c '172\.16\.0\.0/16')"
check "AC-01 contains 172.31.0.0/16"     "1"  "$(printf '%s\n' "${out}" | grep -c '172\.31\.0\.0/16')"
check "AC-01 sixteen 172.x /16 blocks"   "16" "$(printf '%s\n' "${out}" | grep -cE '172\.(1[6-9]|2[0-9]|3[01])\.0\.0/16')"
check "AC-01 contains 192.168.0.0/16"    "1"  "$(printf '%s\n' "${out}" | grep -c '192\.168\.0\.0/16')"
check "AC-01 no non-octet /12 mask" "0" "$(printf '%s\n' "${out}" | grep -c '/12')"
check "AC-01 no 'all' source" "0" "$(printf '%s\n' "${out}" | grep -cE '^host[[:space:]]+all[[:space:]]+all[[:space:]]+all[[:space:]]+all')"

# AC-02: single custom CIDR.
out="$(PGAGROAL_HBA_SOURCE='10.244.0.0/16' build_hba_lines)"
check "AC-02 single line"  "1" "$(printf '%s\n' "${out}" | grep -c '^host')"
check "AC-02 has the CIDR" "1" "$(printf '%s\n' "${out}" | grep -c '10\.244\.0\.0/16')"

# AC-03: multiple CIDRs with whitespace.
out="$(PGAGROAL_HBA_SOURCE=' 10.0.0.0/8 , 192.168.0.0/16 ' build_hba_lines)"
check "AC-03 two lines" "2" "$(printf '%s\n' "${out}" | grep -c '^host')"
check "AC-03 no stray spaces in address" "0" "$(printf '%s\n' "${out}" | grep -cE 'all[[:space:]]+[0-9./]+[[:space:]]+[0-9]')"

# AC-04: explicit `all` opt-out.
out="$(PGAGROAL_HBA_SOURCE='all' build_hba_lines)"
check "AC-04 single line" "1" "$(printf '%s\n' "${out}" | grep -c '^host')"
check "AC-04 all-all-all-all" "1" "$(printf '%s\n' "${out}" | grep -cE '^host[[:space:]]+all[[:space:]]+all[[:space:]]+all[[:space:]]+all')"

# AC-05: empty element (trailing comma) skipped.
out="$(PGAGROAL_HBA_SOURCE='10.0.0.0/8,' build_hba_lines)"
check "AC-05 one line, empty skipped" "1" "$(printf '%s\n' "${out}" | grep -c '^host')"

# AC-06: allow_unknown_users rendered from env.
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
PGAGROAL_HOST='*' PGAGROAL_PORT='6432' PGAGROAL_METRICS_PORT='2346' \
PG_BACKEND_HOST='pg' PG_BACKEND_PORT='5432' MAX_CONNECTIONS='100' \
PGAGROAL_LOG_LEVEL='info' PGAGROAL_ALLOW_UNKNOWN_USERS='false' \
    envsubst < pgagroal.conf.template > "${tmp}/pgagroal.conf"
check "AC-06 allow_unknown_users=false" "1" "$(grep -c '^allow_unknown_users = false$' "${tmp}/pgagroal.conf")"

echo "=== ${pass} passed, ${fail} failed ==="
[ "${fail}" -eq 0 ]
