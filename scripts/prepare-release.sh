#!/usr/bin/env bash
#
# prepare-release.sh — verify release consistency and print release commands.
#
# Does NOT commit, tag, or push. Only inspects and reports.
#
set -euo pipefail

CHECK_ONLY=false
if [[ "${1:-}" = "--check-only" ]]; then
    CHECK_ONLY=true
fi

# ── helpers ───────────────────────────────────────────────────────────────────

die()  { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  OK  $*"; }
warn() { echo "  WARN  $*"; }

# ── preconditions ─────────────────────────────────────────────────────────────

[[ -f "Dockerfile" ]] || die "must be run from the repository root"

echo "=== Release Preparation ==="
echo ""

# ── gather versions ───────────────────────────────────────────────────────────

PROJECT_VERSION=$(cat VERSION 2>/dev/null | tr -d '[:space:]')
CHART_VERSION=$(sed -n 's/^version: //p' helm/pgagroal/Chart.yaml | tr -d '[:space:]')
PGAGROAL_DOCKERFILE=$(sed -n 's/^ARG PGAGROAL_VERSION=\([0-9.]*\)/\1/p' Dockerfile)
PGAGROAL_MAKEFILE=$(sed -n 's/^IMAGE_TAG    := \(.*\)/\1/p' Makefile | tr -d '[:space:]')
PGAGROAL_CHART=$(sed -n 's/^appVersion: "\(.*\)"/\1/p' helm/pgagroal/Chart.yaml)
PGAGROAL_VALUES=$(sed -n 's/^  tag: "\(.*\)"/\1/p' helm/pgagroal/values.yaml | head -1)
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

echo "--- Version consistency ---"
echo ""
echo "  Project version (VERSION)     : ${PROJECT_VERSION}"
echo "  Helm chart version            : ${CHART_VERSION}"
echo "  pgagroal (Dockerfile)         : ${PGAGROAL_DOCKERFILE}"
echo "  pgagroal (Makefile)           : ${PGAGROAL_MAKEFILE}"
echo "  pgagroal (Chart.yaml)         : ${PGAGROAL_CHART}"
echo "  pgagroal (values.yaml)        : ${PGAGROAL_VALUES}"
echo "  Branch                        : ${BRANCH}"
echo "  Commit                        : ${COMMIT}"
echo ""

# ── consistency checks ────────────────────────────────────────────────────────

ERRORS=0

# Project version consistency
if [[ "${PROJECT_VERSION}" = "${CHART_VERSION}" ]]; then
    ok "VERSION matches Chart.yaml version"
else
    warn "VERSION (${PROJECT_VERSION}) != Chart.yaml version (${CHART_VERSION})"
    ERRORS=$((ERRORS + 1))
fi

# pgagroal version consistency across all files
if [[ "${PGAGROAL_DOCKERFILE}" = "${PGAGROAL_MAKEFILE}" ]] \
    && [[ "${PGAGROAL_MAKEFILE}" = "${PGAGROAL_CHART}" ]] \
    && [[ "${PGAGROAL_CHART}" = "${PGAGROAL_VALUES}" ]]; then
    ok "pgagroal version consistent across all files (${PGAGROAL_DOCKERFILE})"
else
    warn "pgagroal version mismatch:"
    warn "  Dockerfile=${PGAGROAL_DOCKERFILE} Makefile=${PGAGROAL_MAKEFILE} Chart=${PGAGROAL_CHART} Values=${PGAGROAL_VALUES}"
    ERRORS=$((ERRORS + 1))
fi

# Clean working tree
if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
    ok "working tree is clean"
else
    warn "working tree has uncommitted changes"
    ERRORS=$((ERRORS + 1))
fi

# Branch check
if [[ "${BRANCH}" = "main" ]]; then
    ok "on main branch"
else
    warn "not on main branch (${BRANCH})"
    ERRORS=$((ERRORS + 1))
fi

# Tag check
TAG="v${PROJECT_VERSION}"
if git tag -l "${TAG}" | grep -q "${TAG}"; then
    warn "tag ${TAG} already exists"
    ERRORS=$((ERRORS + 1))
else
    ok "tag ${TAG} does not exist yet"
fi

# ── Gate F: release hygiene checks (F3–F8) ────────────────────────────────────
# Spec: specifications/project-release/spec.md (ACTIVE)

# F3: CHANGELOG.md has a dated section for the release version
SECTION_START=""
if [[ -f CHANGELOG.md ]]; then
    SECTION_START=$(grep -nE "^## \[${PROJECT_VERSION//./\\.}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}" CHANGELOG.md 2>/dev/null | head -1 | cut -d: -f1 || true)
fi
if [[ -n "${SECTION_START}" ]]; then
    ok "F3: CHANGELOG.md has dated section for ${PROJECT_VERSION}"
else
    warn "F3: CHANGELOG.md has no '## [${PROJECT_VERSION}] - YYYY-MM-DD' section"
    ERRORS=$((ERRORS + 1))
fi

# F4-F6: release class field + class-specific extra requirements
# Only evaluated if F3 found a section to inspect.
CLASS_VALUE=""
if [[ -n "${SECTION_START}" ]]; then
    SECTION_BODY=$(awk -v start="${SECTION_START}" 'NR>start { if (/^## /) exit; print }' CHANGELOG.md)
    CLASS_LINE=$(echo "${SECTION_BODY}" | grep -m1 -vE '^[[:space:]]*$' || true)
    if [[ "${CLASS_LINE}" =~ ^Class:[[:space:]]+(feature|fix|security|breaking-config)[[:space:]]*$ ]]; then
        CLASS_VALUE="${BASH_REMATCH[1]}"
        ok "F4: Class is '${CLASS_VALUE}'"
    else
        warn "F4: ${PROJECT_VERSION} section needs 'Class: <value>' as the first non-blank line, where <value> is one of: feature, fix, security, breaking-config"
        ERRORS=$((ERRORS + 1))
    fi
fi

# F5: breaking-config requires migration doc
if [[ "${CLASS_VALUE}" = "breaking-config" ]]; then
    if [[ -f "docs/operations/migrations/${PROJECT_VERSION}.md" ]]; then
        ok "F5: migration doc docs/operations/migrations/${PROJECT_VERSION}.md exists"
    else
        warn "F5: Class is breaking-config but docs/operations/migrations/${PROJECT_VERSION}.md is missing"
        ERRORS=$((ERRORS + 1))
    fi
fi

# F6: security requires a ### Security subsection
if [[ "${CLASS_VALUE}" = "security" ]]; then
    if echo "${SECTION_BODY}" | grep -qE '^### Security[[:space:]]*$'; then
        ok "F6: ### Security subsection present"
    else
        warn "F6: Class is security but ### Security subsection is missing in the ${PROJECT_VERSION} changelog section"
        ERRORS=$((ERRORS + 1))
    fi
fi

# F7: README.md "Pinned versions" pgagroal row matches Dockerfile pin
if [[ -f README.md ]]; then
    README_PG_PIN=$(sed -n 's/^| pgagroal | \([^ |]*\) |.*/\1/p' README.md | head -1)
    if [[ "${README_PG_PIN}" = "${PGAGROAL_DOCKERFILE}" ]]; then
        ok "F7: README.md Pinned Versions has pgagroal ${PGAGROAL_DOCKERFILE}"
    else
        warn "F7: README.md Pinned Versions pgagroal=${README_PG_PIN:-<missing>}, expected ${PGAGROAL_DOCKERFILE}"
        ERRORS=$((ERRORS + 1))
    fi
fi

# F8: DOCKER_HUB.md quickstart and verify snippets reference the project version
if [[ -f DOCKER_HUB.md ]]; then
    if grep -qF "elevarq/pgagroal:${PROJECT_VERSION}" DOCKER_HUB.md; then
        ok "F8: DOCKER_HUB.md references elevarq/pgagroal:${PROJECT_VERSION}"
    else
        warn "F8: DOCKER_HUB.md does not reference elevarq/pgagroal:${PROJECT_VERSION}"
        ERRORS=$((ERRORS + 1))
    fi
fi

echo ""

if [[ "${ERRORS}" -gt 0 ]]; then
    echo "--- ${ERRORS} issue(s) found. Resolve before releasing. ---"
    if [[ "${CHECK_ONLY}" = true ]]; then
        exit 1
    fi
fi

if [[ "${CHECK_ONLY}" = true ]]; then
    echo "--- All checks passed ---"
    exit 0
fi

# ── release commands ──────────────────────────────────────────────────────────

echo "--- Release commands ---"
echo ""
echo "  # 1. Commit (if there are changes)"
echo "  git add -A && git commit -m 'Release v${PROJECT_VERSION}'"
echo ""
echo "  # 2. Tag"
echo "  git tag -a v${PROJECT_VERSION} -m 'Release v${PROJECT_VERSION} (pgagroal ${PGAGROAL_DOCKERFILE})'"
echo ""
echo "  # 3. Push"
echo "  git push origin main"
echo "  git push origin v${PROJECT_VERSION}"
echo ""
echo "  # 4. Verify"
echo "  git ls-remote origin | grep v${PROJECT_VERSION}"
echo ""
echo "=== Release preparation complete ==="
