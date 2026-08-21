#!/usr/bin/env bash
#
# Helm TLS render test (#109). The catalog/container tests are dockerless and do
# not exercise Helm, which let a Critical slip: the Helm ConfigMap shipped its own
# copy of pgagroal.conf.template WITHOUT ${PGAGROAL_TLS_LINES}, so tls.enabled=true
# set the env + mounted the Secret but rendered plaintext. This asserts the Helm
# chart actually wires TLS.
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
CHART="${REPO_ROOT}/helm/pgagroal"
pass=0
fail=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "${expected}" = "${actual}" ]; then echo "  PASS: ${desc}"; pass=$((pass + 1))
    else echo "  FAIL: ${desc}"; echo "        expected: ${expected}"; echo "        actual:   ${actual}"; fail=$((fail + 1)); fi
}
render() { helm template t "${CHART}" --set credentials.existingSecret=creds "$@" 2>&1; }
neg() { local desc="$1"; shift; if render "$@" >/dev/null 2>&1; then echo "  FAIL: ${desc} rendered but should have failed"; fail=$((fail + 1)); else echo "  PASS: ${desc} rejected"; pass=$((pass + 1)); fi; }

echo "=== Helm TLS Render Test ==="

# The ConfigMap MUST carry the runtime placeholder so the entrypoint can render
# the TLS block (this is the Critical the container tests could not see).
OUT="$(render)"
check "configmap carries \${PGAGROAL_TLS_LINES}" "1" "$(echo "${OUT}" | grep -c 'PGAGROAL_TLS_LINES')"
check "tls off: no PGAGROAL_TLS env"             "0" "$(echo "${OUT}" | grep -cE 'name: PGAGROAL_TLS$')"
check "tls off: no tls-src mount"                "0" "$(echo "${OUT}" | grep -c 'tls-src')"

# TLS on: env + Secret mount + volume.
ON="$(render --set tls.enabled=true --set tls.existingSecret=mytls)"
check "tls on: PGAGROAL_TLS env"                 "1" "$(echo "${ON}" | grep -cE 'name: PGAGROAL_TLS$')"
check "tls on: cert/key env"                     "2" "$(echo "${ON}" | grep -cE 'PGAGROAL_TLS_(CERT|KEY)_FILE')"
check "tls on: tls-src mount"                    "1" "$(echo "${ON}" | grep -c 'mountPath: /etc/pgagroal/tls-src')"
check "tls on: secret volume mytls"              "1" "$(echo "${ON}" | grep -c 'secretName: mytls')"

# Mutual TLS adds the CA env; no tls_cert_auth_mode env (pooler has no such key).
MTLS="$(render --set tls.enabled=true --set tls.existingSecret=mytls --set tls.mutualTLS=true)"
check "mTLS: CA env"                             "1" "$(echo "${MTLS}" | grep -cE 'name: PGAGROAL_TLS_CA_FILE')"

echo "== validateTLS negatives =="
neg "string tls.enabled"        --set-string tls.enabled=false
neg "string tls.mutualTLS"      --set tls.enabled=true --set tls.existingSecret=s --set-string tls.mutualTLS=false
neg "enabled, empty secret"     --set tls.enabled=true --set-string tls.existingSecret=
neg "mutualTLS without enabled" --set tls.mutualTLS=true
neg "certAuthMode verify-full"  --set tls.enabled=true --set tls.existingSecret=s --set tls.certAuthMode=verify-full
neg "invalid secret name"       --set tls.enabled=true --set tls.existingSecret=Bad_Name
neg "whitespace secret name"    --set tls.enabled=true --set-string tls.existingSecret=" "

echo "=== ${pass} passed, ${fail} failed ==="
[ "${fail}" -eq 0 ]
