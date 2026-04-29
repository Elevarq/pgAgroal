#!/usr/bin/env bash
#
# Tests for scripts/prepare-release.sh — Gate F enforcement (F3–F8).
#
# Spec:              specifications/project-release/spec.md
# Acceptance cases:  specifications/project-release/acceptance-cases.md
#
# Each test sets up a temporary worktree, mutates the fixture to a known
# state, runs `prepare-release.sh --check-only`, and asserts the exit code
# and output. The real repo is never modified.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0

# Baseline pgagroal version pinned in the real Dockerfile. Tests pin the
# README pgagroal row to this so F7 (README ↔ Dockerfile match) passes by
# default; tests that exercise F7 mismatch use a different value explicitly.
BASELINE_PGAGROAL=$(sed -n 's/^ARG PGAGROAL_VERSION=\([0-9.]*\)/\1/p' "${SCRIPT_DIR}/Dockerfile")

# ── test harness ──────────────────────────────────────────────────────────────

WORKDIR=""

setup_worktree() {
    WORKDIR=$(mktemp -d)
    cp -a "${SCRIPT_DIR}/." "${WORKDIR}/"
    rm -rf "${WORKDIR}/.git"
    git -C "${WORKDIR}" init -q -b main
    git -C "${WORKDIR}" -c user.email=t@t -c user.name=t add -A
    git -C "${WORKDIR}" -c user.email=t@t -c user.name=t commit -q -m baseline
}

cleanup_worktree() {
    [[ -n "${WORKDIR}" ]] && rm -rf "${WORKDIR}"
    WORKDIR=""
}

# Set the project version in both VERSION and Chart.yaml so F1 passes.
set_project_version() {
    local v="$1"
    echo "${v}" > "${WORKDIR}/VERSION"
    sed -i'' -e "s/^version: .*/version: ${v}/" "${WORKDIR}/helm/pgagroal/Chart.yaml"
}

# Replace the entire CHANGELOG.md with a deterministic fixture.
write_changelog() {
    cat > "${WORKDIR}/CHANGELOG.md"
}

# Set the README pinned-versions row for pgagroal.
set_readme_pgagroal_pin() {
    local v="$1"
    sed -i'' -e "s/^| pgagroal | .* |\$/| pgagroal | ${v} |/" "${WORKDIR}/README.md"
}

# Set the DOCKER_HUB.md project version references.
set_dockerhub_project_pin() {
    local v="$1"
    sed -i'' -e "s|elevarq/pgagroal:[0-9][0-9.]*|elevarq/pgagroal:${v}|g" "${WORKDIR}/DOCKER_HUB.md"
}

run_check() {
    set +e
    OUT=$(cd "${WORKDIR}" && bash scripts/prepare-release.sh --check-only 2>&1)
    RC=$?
    set -e
}

assert_exit() {
    local name="$1" expected="$2" actual="$3"
    if [[ "${actual}" -eq "${expected}" ]]; then
        echo "  PASS: ${name}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${name} (expected exit ${expected}, got ${actual})"
        echo "  ----- output -----"
        # shellcheck disable=SC2001 # sed is the right tool for a per-line prefix
        echo "${OUT}" | sed 's/^/    /'
        echo "  ------------------"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local name="$1" haystack="$2" needle="$3"
    if echo "${haystack}" | grep -qE "${needle}"; then
        echo "  PASS: ${name}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${name} (output does not match /${needle}/)"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local name="$1" haystack="$2" needle="$3"
    if ! echo "${haystack}" | grep -qE "${needle}"; then
        echo "  PASS: ${name}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${name} (output unexpectedly matches /${needle}/)"
        FAIL=$((FAIL + 1))
    fi
}

# ── tests ─────────────────────────────────────────────────────────────────────

echo "=== prepare-release.sh Gate F test suite ==="
echo ""

# --------------------------------------------------------------------------
# AC-08: Changelog dated section present  [gate-F]  (F3 happy)
# --------------------------------------------------------------------------
echo "--- AC-08: dated section present ---"
setup_worktree
set_project_version "1.1.0"
set_readme_pgagroal_pin "${BASELINE_PGAGROAL}"
set_dockerhub_project_pin "1.1.0"
write_changelog <<'EOF'
# Changelog

## [1.1.0] - 2026-04-29

Class: feature

### Added

- New thing.
EOF
git -C "${WORKDIR}" -c user.email=t@t -c user.name=t commit -q -am fixture
run_check
assert_exit "exit 0" 0 "${RC}"
assert_contains "F3 ok" "${OUT}" "F3.*1\\.1\\.0"
cleanup_worktree

# --------------------------------------------------------------------------
# AC-09: Changelog missing dated section  [gate-F] [failure]  (F3 fail)
# --------------------------------------------------------------------------
echo "--- AC-09: dated section missing ---"
setup_worktree
set_project_version "1.1.0"
set_readme_pgagroal_pin "${BASELINE_PGAGROAL}"
set_dockerhub_project_pin "1.1.0"
write_changelog <<'EOF'
# Changelog

## [Unreleased]

### Added

- WIP.
EOF
git -C "${WORKDIR}" -c user.email=t@t -c user.name=t commit -q -am fixture
run_check
assert_exit "exit 1" 1 "${RC}"
assert_contains "F3 cited" "${OUT}" "F3"
assert_contains "names version" "${OUT}" "1\\.1\\.0"
cleanup_worktree

# --------------------------------------------------------------------------
# AC-10: Class field present and valid  [gate-F]  (F4 happy)
# --------------------------------------------------------------------------
echo "--- AC-10: Class field present and valid ---"
setup_worktree
set_project_version "1.1.0"
set_readme_pgagroal_pin "${BASELINE_PGAGROAL}"
set_dockerhub_project_pin "1.1.0"
write_changelog <<'EOF'
# Changelog

## [1.1.0] - 2026-04-29

Class: breaking-config

### Migration

- Vault rotation required.
EOF
mkdir -p "${WORKDIR}/docs/operations/migrations"
echo "# Migration to 1.1.0" > "${WORKDIR}/docs/operations/migrations/1.1.0.md"
git -C "${WORKDIR}" -c user.email=t@t -c user.name=t add -A
git -C "${WORKDIR}" -c user.email=t@t -c user.name=t commit -q -m fixture
run_check
assert_exit "exit 0" 0 "${RC}"
assert_contains "F4 ok with breaking-config" "${OUT}" "F4.*breaking-config"
cleanup_worktree

# --------------------------------------------------------------------------
# AC-10b: Class field missing  [gate-F] [failure]  (F4 fail)
# --------------------------------------------------------------------------
echo "--- AC-10b: Class field missing ---"
setup_worktree
set_project_version "1.1.0"
set_readme_pgagroal_pin "${BASELINE_PGAGROAL}"
set_dockerhub_project_pin "1.1.0"
write_changelog <<'EOF'
# Changelog

## [1.1.0] - 2026-04-29

### Added

- New thing.
EOF
git -C "${WORKDIR}" -c user.email=t@t -c user.name=t commit -q -am fixture
run_check
assert_exit "exit 1" 1 "${RC}"
assert_contains "F4 cited" "${OUT}" "F4"
cleanup_worktree

# --------------------------------------------------------------------------
# AC-10c: Class field invalid value  [gate-F] [failure]  (F4 fail)
# --------------------------------------------------------------------------
echo "--- AC-10c: Class field invalid value ---"
setup_worktree
set_project_version "1.1.0"
set_readme_pgagroal_pin "${BASELINE_PGAGROAL}"
set_dockerhub_project_pin "1.1.0"
write_changelog <<'EOF'
# Changelog

## [1.1.0] - 2026-04-29

Class: experimental

### Added

- New thing.
EOF
git -C "${WORKDIR}" -c user.email=t@t -c user.name=t commit -q -am fixture
run_check
assert_exit "exit 1" 1 "${RC}"
assert_contains "F4 cited" "${OUT}" "F4"
assert_contains "lists valid values" "${OUT}" "feature.*fix.*security.*breaking-config"
cleanup_worktree

# --------------------------------------------------------------------------
# AC-11: breaking-config requires migration doc  [gate-F]  (F5 fail)
# --------------------------------------------------------------------------
echo "--- AC-11: breaking-config without migration doc ---"
setup_worktree
set_project_version "1.1.0"
set_readme_pgagroal_pin "${BASELINE_PGAGROAL}"
set_dockerhub_project_pin "1.1.0"
write_changelog <<'EOF'
# Changelog

## [1.1.0] - 2026-04-29

Class: breaking-config

### Migration

- Vault rotation required.
EOF
# NB: migration doc deliberately not created
git -C "${WORKDIR}" -c user.email=t@t -c user.name=t commit -q -am fixture
run_check
assert_exit "exit 1" 1 "${RC}"
assert_contains "F5 cited" "${OUT}" "F5"
assert_contains "names migration path" "${OUT}" "migrations/1\\.1\\.0\\.md"
cleanup_worktree

# --------------------------------------------------------------------------
# AC-11b: non-breaking does NOT require migration doc  [gate-F]  (F5 n/a)
# --------------------------------------------------------------------------
echo "--- AC-11b: non-breaking does not require migration doc ---"
setup_worktree
set_project_version "1.0.2"
set_readme_pgagroal_pin "${BASELINE_PGAGROAL}"
set_dockerhub_project_pin "1.0.2"
write_changelog <<'EOF'
# Changelog

## [1.0.2] - 2026-04-29

Class: fix

### Fixed

- Small bug.
EOF
git -C "${WORKDIR}" -c user.email=t@t -c user.name=t commit -q -am fixture
run_check
assert_exit "exit 0" 0 "${RC}"
assert_not_contains "F5 not raised" "${OUT}" "F5"
cleanup_worktree

# --------------------------------------------------------------------------
# AC-12: security requires Security subsection  [gate-F]  (F6 fail)
# --------------------------------------------------------------------------
echo "--- AC-12: security without Security subsection ---"
setup_worktree
set_project_version "1.0.3"
set_readme_pgagroal_pin "${BASELINE_PGAGROAL}"
set_dockerhub_project_pin "1.0.3"
write_changelog <<'EOF'
# Changelog

## [1.0.3] - 2026-04-29

Class: security

### Fixed

- Some fix without naming the CVE.
EOF
git -C "${WORKDIR}" -c user.email=t@t -c user.name=t commit -q -am fixture
run_check
assert_exit "exit 1" 1 "${RC}"
assert_contains "F6 cited" "${OUT}" "F6"
cleanup_worktree

# --------------------------------------------------------------------------
# AC-12b: feature/fix has no extra requirement  [gate-F]
# --------------------------------------------------------------------------
echo "--- AC-12b: fix class has no extra requirement ---"
setup_worktree
set_project_version "1.0.2"
set_readme_pgagroal_pin "${BASELINE_PGAGROAL}"
set_dockerhub_project_pin "1.0.2"
write_changelog <<'EOF'
# Changelog

## [1.0.2] - 2026-04-29

Class: fix

### Fixed

- Small bug.
EOF
git -C "${WORKDIR}" -c user.email=t@t -c user.name=t commit -q -am fixture
run_check
assert_exit "exit 0" 0 "${RC}"
assert_not_contains "F5 not raised" "${OUT}" "F5"
assert_not_contains "F6 not raised" "${OUT}" "F6"
cleanup_worktree

# --------------------------------------------------------------------------
# AC-28: README pinned-versions reflects current pin  [gate-F]  (F7 fail)
# --------------------------------------------------------------------------
echo "--- AC-28: README pinned versions stale ---"
setup_worktree
set_project_version "1.1.0"
# Dockerfile pins 2.0.2, but README claims pgagroal 1.0.0 — mismatch
set_readme_pgagroal_pin "1.0.0"
set_dockerhub_project_pin "1.1.0"
write_changelog <<'EOF'
# Changelog

## [1.1.0] - 2026-04-29

Class: feature

### Added

- thing.
EOF
git -C "${WORKDIR}" -c user.email=t@t -c user.name=t commit -q -am fixture
run_check
assert_exit "exit 1" 1 "${RC}"
assert_contains "F7 cited" "${OUT}" "F7"
cleanup_worktree

# --------------------------------------------------------------------------
# AC-29: DOCKER_HUB.md references the release version  [gate-F]  (F8 fail)
# --------------------------------------------------------------------------
echo "--- AC-29: DOCKER_HUB.md references stale version ---"
setup_worktree
set_project_version "1.1.0"
set_readme_pgagroal_pin "${BASELINE_PGAGROAL}"
# DOCKER_HUB.md still references 1.0.1, not the new 1.1.0
set_dockerhub_project_pin "1.0.1"
write_changelog <<'EOF'
# Changelog

## [1.1.0] - 2026-04-29

Class: feature

### Added

- thing.
EOF
git -C "${WORKDIR}" -c user.email=t@t -c user.name=t commit -q -am fixture
run_check
assert_exit "exit 1" 1 "${RC}"
assert_contains "F8 cited" "${OUT}" "F8"
cleanup_worktree

# ── results ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ "${FAIL}" -gt 0 ]]; then
    exit 1
fi
