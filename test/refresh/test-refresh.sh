#!/usr/bin/env bash
#
# Automated tests for scripts/refresh-pgagroal.sh
#
# Tests argument validation, dry-run behavior, version replacement,
# and dirty working tree detection. Uses a temporary git worktree
# to avoid modifying the real repository.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REFRESH="${SCRIPT_DIR}/scripts/refresh-pgagroal.sh"
PASS=0
FAIL=0

# ── test harness ──────────────────────────────────────────────────────────────

WORKDIR=""

setup_worktree() {
    WORKDIR=$(mktemp -d)
    cp -a "${SCRIPT_DIR}/." "${WORKDIR}/"
    # Init a minimal git repo so git-diff checks work
    git -C "${WORKDIR}" init -q
    git -C "${WORKDIR}" add -A
    git -C "${WORKDIR}" commit -q -m "test baseline"
}

cleanup_worktree() {
    [[ -n "${WORKDIR}" ]] && rm -rf "${WORKDIR}"
    WORKDIR=""
}

assert_exit() {
    local name="$1" expected="$2" actual="$3"
    if [[ "${actual}" -eq "${expected}" ]]; then
        echo "  PASS: ${name}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${name} (expected exit ${expected}, got ${actual})"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local name="$1" haystack="$2" needle="$3"
    if echo "${haystack}" | grep -qi "${needle}"; then
        echo "  PASS: ${name}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${name} (output does not contain '${needle}')"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contains() {
    local name="$1" file="$2" pattern="$3"
    if grep -q "${pattern}" "${file}"; then
        echo "  PASS: ${name}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${name} (${file} does not contain '${pattern}')"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_unchanged() {
    local name="$1" dir="$2"
    if git -C "${dir}" diff --quiet; then
        echo "  PASS: ${name}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${name} (files were modified)"
        FAIL=$((FAIL + 1))
    fi
}

# ── tests ─────────────────────────────────────────────────────────────────────

echo "=== refresh-pgagroal.sh test suite ==="
echo ""

# --- AC-02: invalid version (missing component) ---
echo "--- AC-02: invalid version format (2.1) ---"
set +e
out=$(bash "${REFRESH}" --version 2.1 2>&1)
rc=$?
set -e
assert_exit "exit code" 1 "${rc}"
assert_contains "error message" "${out}" "invalid version format"

# --- AC-03: invalid version (v prefix) ---
echo "--- AC-03: invalid version format (v2.1.0) ---"
set +e
out=$(bash "${REFRESH}" --version v2.1.0 2>&1)
rc=$?
set -e
assert_exit "exit code" 1 "${rc}"
assert_contains "error message" "${out}" "invalid version format"

# --- AC-04: invalid version (pre-release) ---
echo "--- AC-04: invalid version format (2.1.0-rc1) ---"
set +e
out=$(bash "${REFRESH}" --version 2.1.0-rc1 2>&1)
rc=$?
set -e
assert_exit "exit code" 1 "${rc}"
assert_contains "error message" "${out}" "invalid version format"

# --- AC-05: missing --version ---
echo "--- AC-05: missing --version ---"
set +e
out=$(bash "${REFRESH}" 2>&1)
rc=$?
set -e
assert_exit "exit code" 1 "${rc}"
assert_contains "usage shown" "${out}" "Usage:"

# --- AC-13: --help ---
echo "--- AC-13: --help ---"
set +e
out=$(bash "${REFRESH}" --help 2>&1)
rc=$?
set -e
assert_exit "exit code" 0 "${rc}"
assert_contains "usage shown" "${out}" "Usage:"
assert_contains "examples shown" "${out}" "Examples:"

# --- AC-08: dirty working tree ---
echo "--- AC-08: dirty working tree ---"
setup_worktree
echo "dirty" >> "${WORKDIR}/VERSION"
set +e
out=$(cd "${WORKDIR}" && bash "${WORKDIR}/scripts/refresh-pgagroal.sh" --version 2.1.0 2>&1)
rc=$?
set -e
assert_exit "exit code" 1 "${rc}"
assert_contains "error message" "${out}" "uncommitted"
cleanup_worktree

# --- AC-09: dirty tree allowed in dry-run ---
echo "--- AC-09: dirty tree allowed in dry-run ---"
setup_worktree
echo "dirty" >> "${WORKDIR}/VERSION"
set +e
out=$(cd "${WORKDIR}" && bash "${WORKDIR}/scripts/refresh-pgagroal.sh" --version 2.1.0 --dry-run 2>&1)
rc=$?
set -e
assert_exit "exit code" 0 "${rc}"
assert_contains "dry run label" "${out}" "DRY RUN"
cleanup_worktree

# --- AC-10: dry-run does not modify files ---
echo "--- AC-10: dry-run does not modify files ---"
setup_worktree
set +e
out=$(cd "${WORKDIR}" && bash "${WORKDIR}/scripts/refresh-pgagroal.sh" --version 9.9.9 --dry-run 2>&1)
rc=$?
set -e
assert_exit "exit code" 0 "${rc}"
assert_contains "shows changes" "${out}" "9.9.9"
assert_file_unchanged "no files modified" "${WORKDIR}"
cleanup_worktree

# --- AC-01: version replacement (skip tests/build for speed) ---
echo "--- AC-01: version replacement (files only) ---"
setup_worktree
# We can't build inside the test, so we test just the file replacement
# by calling with --skip-tests and mocking docker build via PATH override
mkdir -p "${WORKDIR}/.mockbin"
cat > "${WORKDIR}/.mockbin/docker" << 'MOCK'
#!/bin/sh
# Mock docker: accept build, succeed silently
if [ "$1" = "build" ]; then exit 0; fi
exec /usr/bin/docker "$@"
MOCK
chmod +x "${WORKDIR}/.mockbin/docker"
set +e
out=$(cd "${WORKDIR}" && PATH="${WORKDIR}/.mockbin:${PATH}" bash "${WORKDIR}/scripts/refresh-pgagroal.sh" --version 3.0.0 --skip-tests 2>&1)
rc=$?
set -e
assert_exit "exit code" 0 "${rc}"
assert_file_contains "Dockerfile updated" "${WORKDIR}/Dockerfile" "ARG PGAGROAL_VERSION=3.0.0"
assert_file_contains "Makefile updated" "${WORKDIR}/Makefile" "IMAGE_TAG    := 3.0.0"
assert_file_contains "Chart.yaml updated" "${WORKDIR}/helm/pgagroal/Chart.yaml" 'appVersion: "3.0.0"'
assert_file_contains "values.yaml updated" "${WORKDIR}/helm/pgagroal/values.yaml" 'tag: "3.0.0"'
assert_contains "summary shows version" "${out}" "Version"
assert_contains "summary shows success" "${out}" "SUCCESS"
cleanup_worktree

# --- AC-11: idempotency ---
echo "--- AC-11: idempotency (same version) ---"
setup_worktree
mkdir -p "${WORKDIR}/.mockbin"
cat > "${WORKDIR}/.mockbin/docker" << 'MOCK'
#!/bin/sh
if [ "$1" = "build" ]; then exit 0; fi
exec /usr/bin/docker "$@"
MOCK
chmod +x "${WORKDIR}/.mockbin/docker"
set +e
out=$(cd "${WORKDIR}" && PATH="${WORKDIR}/.mockbin:${PATH}" bash "${WORKDIR}/scripts/refresh-pgagroal.sh" --version 2.0.2 --skip-tests 2>&1)
rc=$?
set -e
assert_exit "exit code" 0 "${rc}"
assert_file_contains "Dockerfile unchanged" "${WORKDIR}/Dockerfile" "ARG PGAGROAL_VERSION=2.0.2"
assert_contains "summary shows success" "${out}" "SUCCESS"
cleanup_worktree

# --- AC-12: --update-changelog ---
echo "--- AC-12: --update-changelog ---"
setup_worktree
mkdir -p "${WORKDIR}/.mockbin"
cat > "${WORKDIR}/.mockbin/docker" << 'MOCK'
#!/bin/sh
if [ "$1" = "build" ]; then exit 0; fi
exec /usr/bin/docker "$@"
MOCK
chmod +x "${WORKDIR}/.mockbin/docker"
set +e
out=$(cd "${WORKDIR}" && PATH="${WORKDIR}/.mockbin:${PATH}" bash "${WORKDIR}/scripts/refresh-pgagroal.sh" --version 3.0.0 --skip-tests --update-changelog 2>&1)
rc=$?
set -e
assert_exit "exit code" 0 "${rc}"
assert_file_contains "changelog has unreleased" "${WORKDIR}/CHANGELOG.md" "Unreleased"
assert_file_contains "changelog has bump line" "${WORKDIR}/CHANGELOG.md" "Bump pgagroal from 2.0.2 to 3.0.0"
assert_file_contains "changelog preserves old content" "${WORKDIR}/CHANGELOG.md" "0.1.0"
cleanup_worktree

# --- AC-16: wrong working directory ---
echo "--- AC-16: wrong working directory ---"
set +e
out=$(cd /tmp && bash "${REFRESH}" --version 2.1.0 2>&1)
rc=$?
set -e
assert_exit "exit code" 1 "${rc}"
assert_contains "error message" "${out}" "repository root"

# ── results ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ "${FAIL}" -gt 0 ]]; then
    exit 1
fi
