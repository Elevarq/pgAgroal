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
check "AC-01 all 18 lines use scram-sha-256 method" "18" "$(printf '%s\n' "${out}" | grep -cE '[[:space:]]scram-sha-256$')"
check "AC-01 no trust/all auth method" "0" "$(printf '%s\n' "${out}" | grep -cE '[[:space:]](trust|all)$')"

# AC-02: single custom CIDR.
out="$(PGAGROAL_HBA_SOURCE='10.244.0.0/16' build_hba_lines)"
check "AC-02 single line"  "1" "$(printf '%s\n' "${out}" | grep -c '^host')"
check "AC-02 has the CIDR" "1" "$(printf '%s\n' "${out}" | grep -c '10\.244\.0\.0/16')"

# AC-03: multiple CIDRs with whitespace.
out="$(PGAGROAL_HBA_SOURCE=' 10.0.0.0/8 , 192.168.0.0/16 ' build_hba_lines)"
check "AC-03 two lines" "2" "$(printf '%s\n' "${out}" | grep -c '^host')"
check "AC-03 no stray spaces in address" "0" "$(printf '%s\n' "${out}" | grep -cE 'all[[:space:]]+[0-9./]+[[:space:]]+[0-9]')"

# AC-04: explicit `all` opt-out keeps the scram-sha-256 method.
out="$(PGAGROAL_HBA_SOURCE='all' build_hba_lines)"
check "AC-04 single line" "1" "$(printf '%s\n' "${out}" | grep -c '^host')"
check "AC-04 all-all-all-scram" "1" "$(printf '%s\n' "${out}" | grep -cE '^host[[:space:]]+all[[:space:]]+all[[:space:]]+all[[:space:]]+scram-sha-256$')"

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

# AC-07: hardened default — unset PGAGROAL_ALLOW_UNKNOWN_USERS renders false.
# Applies the entrypoint's own default expression so the test pins the
# shipped default, not an arbitrary value.
unset PGAGROAL_ALLOW_UNKNOWN_USERS
PGAGROAL_HOST='*' PGAGROAL_PORT='6432' PGAGROAL_METRICS_PORT='2346' \
PG_BACKEND_HOST='pg' PG_BACKEND_PORT='5432' MAX_CONNECTIONS='100' \
PGAGROAL_LOG_LEVEL='info' \
PGAGROAL_ALLOW_UNKNOWN_USERS="${PGAGROAL_ALLOW_UNKNOWN_USERS:-false}" \
    envsubst < pgagroal.conf.template > "${tmp}/pgagroal-default.conf"
check "AC-07 default allow_unknown_users=false" "1" "$(grep -c '^allow_unknown_users = false$' "${tmp}/pgagroal-default.conf")"

# AC-08: injection / invalid entries are dropped, never a `trust` rule.
out="$(PGAGROAL_HBA_SOURCE='all trust #' build_hba_lines 2>/dev/null)"
check "AC-08 injection emits no host line" "0" "$(printf '%s\n' "${out}" | grep -c '^host')"
check "AC-08 no trust method anywhere"     "0" "$(printf '%s\n' "${out}" | grep -cE '[[:space:]]trust([[:space:]]|$)')"
for bad in 'foo' '10.0.0.0/8 trust' '0.0.0.0/0;' 'all;drop'; do
    out="$(PGAGROAL_HBA_SOURCE="${bad}" build_hba_lines 2>/dev/null)"
    check "AC-08 invalid '${bad}' dropped" "0" "$(printf '%s\n' "${out}" | grep -c '^host')"
done
# Valid entries survive while the injection entry between them is dropped.
out="$(PGAGROAL_HBA_SOURCE='10.0.0.0/8, all trust #, 192.168.0.0/16' build_hba_lines 2>/dev/null)"
check "AC-08 two valid lines kept"    "2" "$(printf '%s\n' "${out}" | grep -c '^host')"
check "AC-08 valid 10.0.0.0/8 kept"   "1" "$(printf '%s\n' "${out}" | grep -c '10\.0\.0\.0/8')"
check "AC-08 valid 192.168.0.0/16 kept" "1" "$(printf '%s\n' "${out}" | grep -c '192\.168\.0\.0/16')"
check "AC-08 all lines scram-sha-256" "2" "$(printf '%s\n' "${out}" | grep -cE '[[:space:]]scram-sha-256$')"

# AC-09: semantic validation — reject out-of-range octets, non-octet masks, and
# glob metacharacters; accept octet-aligned masks and 0.0.0.0/0.
for bad in '999.999.999.999/24' '256.0.0.0/8' '10.0.0.0/20' '10.0.0.0/33' '10.0.0/8' '*' '10.*.0.0/16'; do
    out="$(PGAGROAL_HBA_SOURCE="${bad}" build_hba_lines 2>/dev/null)"
    check "AC-09 invalid '${bad}' dropped" "0" "$(printf '%s\n' "${out}" | grep -c '^host')"
done
for good in '10.0.0.0/8' '192.168.1.0/24' '10.1.2.3/32' '0.0.0.0/0' 'all'; do
    out="$(PGAGROAL_HBA_SOURCE="${good}" build_hba_lines 2>/dev/null)"
    check "AC-09 valid '${good}' kept" "1" "$(printf '%s\n' "${out}" | grep -c '^host')"
done
# A glob metacharacter must not expand to filenames (unquoted-expansion guard).
out="$(cd / && PGAGROAL_HBA_SOURCE='*' build_hba_lines 2>/dev/null)"
check "AC-09 '*' does not glob to files" "0" "$(printf '%s\n' "${out}" | grep -c '^host')"

echo "=== ${pass} passed, ${fail} failed ==="
[ "${fail}" -eq 0 ]
