#!/usr/bin/env bash
#
# Validation test: frontend TLS (client <-> pooler) (#103).
#
# Dockerless — sources the entrypoint and exercises tls_enabled, build_tls_lines,
# install_tls_material, and the envsubst rendering of pgagroal.conf.template.
# Verifies specifications/tls-frontend/acceptance-cases.md.
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"

# Use a writable CONF_DIR so install_tls_material can write TLS material; the
# entrypoint derives TLS_DIR from CONF_DIR at source time.
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
export CONF_DIR="${WORK}/etc"
mkdir -p "${CONF_DIR}"

cd "${REPO_ROOT}" || exit 1
# shellcheck source=/dev/null
source ./entrypoint.sh

pass=0
fail=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "${expected}" = "${actual}" ]; then
        echo "  PASS: ${desc}"; pass=$((pass + 1))
    else
        echo "  FAIL: ${desc}"; echo "        expected: ${expected}"; echo "        actual:   ${actual}"; fail=$((fail + 1))
    fi
}

# Throwaway PEM-ish material (contents are irrelevant to rendering/install).
src="${WORK}/src"; mkdir -p "${src}"
printf 'CERT\n' > "${src}/tls.crt"
printf 'KEY\n'  > "${src}/tls.key"; chmod 0644 "${src}/tls.key"
printf 'CA\n'   > "${src}/ca.crt"

echo "=== Frontend TLS Test ==="

# AC-01: TLS off by default — no TLS keys rendered.
unset PGAGROAL_TLS PGAGROAL_TLS_CA_FILE PGAGROAL_TLS_CERT_FILE PGAGROAL_TLS_KEY_FILE PGAGROAL_TLS_CERT_AUTH_MODE
export PGAGROAL_TLS="${PGAGROAL_TLS:-off}"
PGAGROAL_TLS_LINES="$(build_tls_lines)"; export PGAGROAL_TLS_LINES
PGAGROAL_HOST='*' PGAGROAL_PORT='6432' PGAGROAL_METRICS_PORT='2346' \
PG_BACKEND_HOST='pg' PG_BACKEND_PORT='5432' MAX_CONNECTIONS='100' \
PGAGROAL_LOG_LEVEL='info' PGAGROAL_ALLOW_UNKNOWN_USERS='false' \
    envsubst < pgagroal.conf.template > "${WORK}/off.conf"
check "AC-01 no tls keys when off" "0" "$(grep -cE '^tls' "${WORK}/off.conf")"

# AC-02: tls_enabled truthiness.
for v in on true 1 yes ON True; do PGAGROAL_TLS="$v" tls_enabled && r=0 || r=1; check "AC-02 '$v' enables" "0" "$r"; done
for v in off false 0 no "" garbage; do PGAGROAL_TLS="$v" tls_enabled && r=0 || r=1; check "AC-02 '$v' disables" "1" "$r"; done

# AC-03: cert + key only.
out="$(PGAGROAL_TLS=on PGAGROAL_TLS_CA_FILE='' build_tls_lines)"
check "AC-03 tls = on"        "1" "$(printf '%s\n' "$out" | grep -c '^tls = on$')"
check "AC-03 cert file"       "1" "$(printf '%s\n' "$out" | grep -c 'server.crt$')"
check "AC-03 key file"        "1" "$(printf '%s\n' "$out" | grep -c 'server.key$')"
check "AC-03 no ca line"      "0" "$(printf '%s\n' "$out" | grep -c 'tls_ca_file')"
check "AC-03 no auth mode"    "0" "$(printf '%s\n' "$out" | grep -c 'tls_cert_auth_mode')"

# AC-04: cert + key + CA, default auth mode verify-ca.
out="$(PGAGROAL_TLS=on PGAGROAL_TLS_CA_FILE="${src}/ca.crt" build_tls_lines)"
check "AC-04 ca line"         "1" "$(printf '%s\n' "$out" | grep -c 'tls_ca_file = .*ca.crt$')"
check "AC-04 default verify-ca" "1" "$(printf '%s\n' "$out" | grep -c '^tls_cert_auth_mode = verify-ca$')"

# AC-05: verify-full honored.
out="$(PGAGROAL_TLS=on PGAGROAL_TLS_CA_FILE="${src}/ca.crt" PGAGROAL_TLS_CERT_AUTH_MODE=verify-full build_tls_lines)"
check "AC-05 verify-full" "1" "$(printf '%s\n' "$out" | grep -c '^tls_cert_auth_mode = verify-full$')"

# AC-06: install key at 0600, cert at 0644.
PGAGROAL_TLS=on PGAGROAL_TLS_CERT_FILE="${src}/tls.crt" PGAGROAL_TLS_KEY_FILE="${src}/tls.key" PGAGROAL_TLS_CA_FILE='' install_tls_material
check "AC-06 key is 0600"  "600"  "$(stat -f '%Lp' "${TLS_DIR}/server.key" 2>/dev/null || stat -c '%a' "${TLS_DIR}/server.key")"
check "AC-06 cert is 0644" "644"  "$(stat -f '%Lp' "${TLS_DIR}/server.crt" 2>/dev/null || stat -c '%a' "${TLS_DIR}/server.crt")"

# AC-07: fail closed on missing key.
if PGAGROAL_TLS=on PGAGROAL_TLS_CERT_FILE="${src}/tls.crt" PGAGROAL_TLS_KEY_FILE="${WORK}/nope.key" PGAGROAL_TLS_CA_FILE='' install_tls_material 2>/dev/null; then r=0; else r=1; fi
check "AC-07 missing key fails" "1" "$r"

# AC-08: invalid auth mode rejected.
if PGAGROAL_TLS=on PGAGROAL_TLS_CA_FILE="${src}/ca.crt" PGAGROAL_TLS_CERT_AUTH_MODE=bogus build_tls_lines >/dev/null 2>&1; then r=0; else r=1; fi
check "AC-08 bogus auth mode fails" "1" "$r"

# AC-09: TLS lines render into [pgagroal]; [primary] unchanged.
PGAGROAL_TLS_LINES="$(PGAGROAL_TLS=on PGAGROAL_TLS_CA_FILE='' build_tls_lines)"; export PGAGROAL_TLS_LINES
PGAGROAL_HOST='*' PGAGROAL_PORT='6432' PGAGROAL_METRICS_PORT='2346' \
PG_BACKEND_HOST='pg' PG_BACKEND_PORT='5432' MAX_CONNECTIONS='100' \
PGAGROAL_LOG_LEVEL='info' PGAGROAL_ALLOW_UNKNOWN_USERS='false' \
    envsubst < pgagroal.conf.template > "${WORK}/on.conf"
check "AC-09 tls=on rendered" "1" "$(grep -c '^tls = on$' "${WORK}/on.conf")"
check "AC-09 tls before [primary]" "1" "$(awk '/^tls = on$/{t=NR} /^\[primary\]$/{p=NR} END{print (t>0 && t<p)?1:0}' "${WORK}/on.conf")"
check "AC-09 [primary] host intact" "1" "$(grep -c '^host = pg$' "${WORK}/on.conf")"

echo "=== ${pass} passed, ${fail} failed ==="
[ "${fail}" -eq 0 ]
