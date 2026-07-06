#!/usr/bin/env bash
#
# Validation test: no static credentials in the tracked tree.
#
# Spec : specifications/no-static-credentials/spec.md
# Cases: AC-01 (literal scan), AC-02 (chart renders by-reference only),
#        AC-03 (placeholders allowed), AC-04 (scan catches an
#        introduced literal), AC-05 (compose fails fast without env —
#        asserted via compose-pgexporter-integration AC-07).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
cd "${SCRIPT_DIR}"

FAILURES=0

# Ban list (AC-01). Historical working-credential literals and the
# structural pattern of an inline chart password. Assembled from parts
# so this file does not match its own patterns when scanned by other
# tools. CHANGELOG.md is excluded: it records the removal history in
# prose (spec I1); gitleaks covers it as the general scanner.
LEGACY_PG_LITERAL="test""pass"
LEGACY_EXPORTER_LITERAL="PGEXPORTER_PASSWORD[:=][[:space:]]*['\"]?pgexporter"
SQL_LITERAL_PASSWORD="WITH LOGIN PASSWORD '[^<:$]"
INLINE_CHART_PASSWORD="credentials\.""password"

BAN_PATTERNS=(
    "${LEGACY_PG_LITERAL}"
    "${LEGACY_EXPORTER_LITERAL}"
    "${SQL_LITERAL_PASSWORD}"
    "${INLINE_CHART_PASSWORD}"
)

SCAN_EXCLUDES=(
    ":(exclude)test/validation/no-static-credentials-test.sh"
    ":(exclude)CHANGELOG.md"
)

scan_tree() {
    local pattern="$1"
    git grep -n -I -E "${pattern}" -- . "${SCAN_EXCLUDES[@]}"
}

echo "=== No-static-credentials validation ==="

# --- AC-01 / AC-03: tracked tree is free of banned literals ---------------
echo "--- AC-01: scan tracked tree for credential literals ---"
for pattern in "${BAN_PATTERNS[@]}"; do
    if hits="$(scan_tree "${pattern}")"; then
        echo "FAIL: banned credential pattern matched (${pattern}):"
        echo "${hits}"
        FAILURES=$((FAILURES + 1))
    fi
done
[ "${FAILURES}" -eq 0 ] && echo "  tracked tree clean"

# --- AC-04: the scan itself catches an introduced literal -----------------
echo "--- AC-04: scan self-check on a seeded literal ---"
selfcheck_file="$(mktemp)"
printf 'POSTGRES_PASSWORD: %s\n' "${LEGACY_PG_LITERAL}" > "${selfcheck_file}"
if grep -q -E "${LEGACY_PG_LITERAL}" "${selfcheck_file}"; then
    echo "  self-check pattern fires as expected"
else
    echo "FAIL: seeded credential literal was not detected (AC-04)"
    FAILURES=$((FAILURES + 1))
fi
rm -f "${selfcheck_file}"

# --- AC-02: chart renders by-reference only --------------------------------
echo "--- AC-02: helm template renders no Secret, no credential value ---"
if ! command -v helm >/dev/null 2>&1; then
    echo "FAIL: helm is required for AC-02 (brew install helm)"
    exit 1
fi

check_render() {
    local label="$1"; shift
    local rendered
    if ! rendered="$(helm template pgagroal helm/pgagroal --set postgresql.host=pg-host "$@" 2>&1)"; then
        echo "FAIL: helm template failed for ${label}:"
        echo "${rendered}" | tail -5
        FAILURES=$((FAILURES + 1))
        return
    fi
    if echo "${rendered}" | grep -q '^kind: Secret'; then
        echo "FAIL: ${label} renders a Secret; the chart must be existingSecret-only (R2)"
        FAILURES=$((FAILURES + 1))
        return
    fi
    for pattern in "${BAN_PATTERNS[@]}"; do
        if echo "${rendered}" | grep -q -E "${pattern}"; then
            echo "FAIL: ${label} render contains a banned credential pattern (${pattern})"
            FAILURES=$((FAILURES + 1))
            return
        fi
    done
    echo "  ${label}: renders, no Secret, no credential value"
}

check_render "default values"
check_render "pgexporter enabled" --set pgexporter.enabled=true

# ---------------------------------------------------------------------------
if [ "${FAILURES}" -gt 0 ]; then
    echo "=== FAILED: ${FAILURES} finding(s) ==="
    exit 1
fi
echo "=== PASSED ==="
