#!/usr/bin/env bash
#
# Validation test: network and bind hardening (#49, v1.4.0 hardened defaults).
#
# Renders the Helm chart with `helm template` and inspects the shipped
# pgexporter config. Verifies the acceptance cases in
# specifications/network-and-bind-hardening/acceptance-cases.md.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
cd "${REPO_ROOT}"

CHART="helm/pgagroal"
COMMON=(--set credentials.username=u --set credentials.password=p --set postgresql.host=h)

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

echo "=== Network and Bind Hardening Test ==="

# AC-01: default render is an enabled, same-namespace NetworkPolicy.
default="$(helm template t "${CHART}" "${COMMON[@]}")"
np_default="$(helm template t "${CHART}" "${COMMON[@]}" --show-only templates/networkpolicy.yaml)"
check "AC-01 one NetworkPolicy rendered" "1" "$(printf '%s\n' "${default}" | grep -c '^kind: NetworkPolicy$')"
check "AC-01 same-namespace podSelector: {}" "1" "$(printf '%s\n' "${np_default}" | grep -cE '^\s*-\s*podSelector:\s*\{\}\s*$')"
check "AC-01 pooler port 6432 in policy ingress" "1" "$(printf '%s\n' "${np_default}" | grep -cE 'port:\s*6432')"

# Hardened config defaults visible in the rendered chart.
check "configmap has no 'host all all all all'" "0" "$(printf '%s\n' "${default}" | grep -cE 'host[[:space:]]+all[[:space:]]+all[[:space:]]+all[[:space:]]+all')"
check "deployment sets PGAGROAL_ALLOW_UNKNOWN_USERS=false" "1" "$(printf '%s\n' "${default}" | grep -A1 'name: PGAGROAL_ALLOW_UNKNOWN_USERS' | grep -c 'value: "false"')"

# AC-02: NetworkPolicy can be disabled.
disabled="$(helm template t "${CHART}" "${COMMON[@]}" --set networkPolicy.enabled=false)"
check "AC-02 no NetworkPolicy when disabled" "0" "$(printf '%s\n' "${disabled}" | grep -c '^kind: NetworkPolicy$')"

# AC-03: no same-namespace + no selectors denies all ingress.
denied="$(helm template t "${CHART}" "${COMMON[@]}" --set networkPolicy.allowSameNamespace=false)"
check "AC-03 NetworkPolicy still rendered" "1" "$(printf '%s\n' "${denied}" | grep -c '^kind: NetworkPolicy$')"
check "AC-03 no podSelector ingress from-entry" "0" "$(printf '%s\n' "${denied}" | grep -cE '^\s*-\s*podSelector:\s*\{\}\s*$')"

# AC-04: egress unconstrained by default; opt-in via restrictEgress.
check "AC-04 default policyTypes has no Egress" "0" "$(printf '%s\n' "${np_default}" | grep -cE '^\s*-\s*Egress\s*$')"
check "AC-04 default has no egress block" "0" "$(printf '%s\n' "${np_default}" | grep -cE '^\s*egress:\s*$')"
check "AC-04 default has no 0.0.0.0/0" "0" "$(printf '%s\n' "${np_default}" | grep -cE 'cidr:\s*"0\.0\.0\.0/0"')"
egr="$(helm template t "${CHART}" "${COMMON[@]}" --set networkPolicy.restrictEgress=true --show-only templates/networkpolicy.yaml)"
check "AC-04 restrictEgress adds Egress policyType" "1" "$(printf '%s\n' "${egr}" | grep -cE '^\s*-\s*Egress\s*$')"
check "AC-04 restrictEgress default egress 0.0.0.0/0" "1" "$(printf '%s\n' "${egr}" | grep -cE 'cidr:\s*"0\.0\.0\.0/0"')"
narrowed="$(helm template t "${CHART}" "${COMMON[@]}" --set networkPolicy.restrictEgress=true --set 'networkPolicy.egress.backendCIDRs[0]=10.0.5.10/32' --show-only templates/networkpolicy.yaml)"
check "AC-04 narrowed egress has 10.0.5.10/32" "1" "$(printf '%s\n' "${narrowed}" | grep -cE 'cidr:\s*"10\.0\.5\.10/32"')"
check "AC-04 narrowed egress drops 0.0.0.0/0" "0" "$(printf '%s\n' "${narrowed}" | grep -cE 'cidr:\s*"0\.0\.0\.0/0"')"

# AC-05: pgexporter binds 0.0.0.0, not the `*` wildcard.
check "AC-05 pgexporter host = 0.0.0.0" "1" "$(grep -cE '^host = 0\.0\.0\.0$' pgexporter/pgexporter.conf.template)"
check "AC-05 pgexporter no host = *" "0" "$(grep -cE '^host = \*$' pgexporter/pgexporter.conf.template)"

echo "=== ${pass} passed, ${fail} failed ==="
[ "${fail}" -eq 0 ]
