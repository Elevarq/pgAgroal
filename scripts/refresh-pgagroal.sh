#!/usr/bin/env bash
#
# refresh-pgagroal.sh — update the bundled pgagroal upstream version,
# rebuild, test, and print a release summary.
#
# See specifications/release-refresh/spec.md for the full specification.
#
set -euo pipefail

# ── constants ─────────────────────────────────────────────────────────────────

TARGETS=(
    "Dockerfile"
    "Makefile"
    "helm/pgagroal/Chart.yaml"
    "helm/pgagroal/values.yaml"
)
CHANGELOG="CHANGELOG.md"
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

# ── defaults ──────────────────────────────────────────────────────────────────

TARGET_VERSION=""
DRY_RUN=false
SKIP_TESTS=false
UPDATE_CHANGELOG=false

# ── helpers ───────────────────────────────────────────────────────────────────

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "  $*"; }
step() { echo "--- $*"; }

usage() {
    cat <<'USAGE'
Usage: scripts/refresh-pgagroal.sh --version <x.y.z> [OPTIONS]

Update the bundled pgagroal upstream version, rebuild, and validate.

Required:
  --version <x.y.z>    Target pgagroal upstream version (e.g. 2.1.0)

Options:
  --dry-run             Show what would change without modifying files
  --skip-tests          Skip test suite after build
  --update-changelog    Prepend an [Unreleased] entry to CHANGELOG.md
  --help                Show this help message

Examples:
  scripts/refresh-pgagroal.sh --version 2.1.0 --dry-run
  scripts/refresh-pgagroal.sh --version 2.1.0
  scripts/refresh-pgagroal.sh --version 2.1.0 --skip-tests --update-changelog
USAGE
    exit "${1:-0}"
}

recovery_hint() {
    echo ""
    echo "Files may have been modified. To restore:"
    echo "  git checkout -- ${TARGETS[*]} ${CHANGELOG}"
}

# ── argument parsing ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            shift
            TARGET_VERSION="${1:-}"
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --skip-tests)
            SKIP_TESTS=true
            ;;
        --update-changelog)
            UPDATE_CHANGELOG=true
            ;;
        --help|-h)
            usage
            ;;
        *)
            die "unknown argument: $1. Use --help for usage."
            ;;
    esac
    shift
done

# ── precondition checks ──────────────────────────────────────────────────────

# P1: version format
if [[ -z "${TARGET_VERSION}" ]]; then
    echo "ERROR: --version is required." >&2
    echo "" >&2
    usage 1
fi
if ! echo "${TARGET_VERSION}" | grep -qE "${VERSION_RE}"; then
    die "invalid version format '${TARGET_VERSION}'. Expected: x.y.z (e.g. 2.1.0)"
fi

# P2: required tools
missing_tools=()
for tool in docker git sed grep; do
    command -v "${tool}" >/dev/null 2>&1 || missing_tools+=("${tool}")
done
if [[ ${#missing_tools[@]} -gt 0 ]]; then
    die "missing required tools: ${missing_tools[*]}"
fi

# P3: repository root
if [[ ! -f "Dockerfile" ]]; then
    die "must be run from the repository root (Dockerfile not found in $(pwd))"
fi

# P4: clean working tree (skipped in dry-run)
if [[ "${DRY_RUN}" = false ]]; then
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        echo "ERROR: working tree has uncommitted changes." >&2
        git status --short >&2
        die "commit or stash changes before running refresh (or use --dry-run)"
    fi
fi

# ── read current version ─────────────────────────────────────────────────────

CURRENT_VERSION=$(sed -n 's/^ARG PGAGROAL_VERSION=\([0-9.]*\)/\1/p' Dockerfile)
if [[ -z "${CURRENT_VERSION}" ]]; then
    die "could not read current PGAGROAL_VERSION from Dockerfile"
fi

echo "=== pgagroal upstream version refresh ==="
echo "  Current : ${CURRENT_VERSION}"
echo "  Target  : ${TARGET_VERSION}"
if [[ "${DRY_RUN}" = true ]]; then
    echo "  Mode    : DRY RUN"
fi
echo ""

# ── file updates ──────────────────────────────────────────────────────────────

update_file() {
    local file="$1" pattern="$2" replacement="$3" description="$4"

    if [[ "${DRY_RUN}" = true ]]; then
        local current_match
        current_match=$(grep -n "${pattern}" "${file}" | head -1)
        info "[dry-run] ${file}: ${description}"
        info "  current: ${current_match}"
        info "  new:     ${replacement}"
        return 0
    fi

    if ! grep -q "${pattern}" "${file}"; then
        die "pattern '${pattern}' not found in ${file}"
    fi

    sed -i'' -e "s|${pattern}|${replacement}|" "${file}"
    info "${file}: ${description}"
}

step "Updating version references"

update_file "Dockerfile" \
    "ARG PGAGROAL_VERSION=.*" \
    "ARG PGAGROAL_VERSION=${TARGET_VERSION}" \
    "ARG PGAGROAL_VERSION → ${TARGET_VERSION}"

update_file "Makefile" \
    "IMAGE_TAG    := .*" \
    "IMAGE_TAG    := ${TARGET_VERSION}" \
    "IMAGE_TAG → ${TARGET_VERSION}"

update_file "helm/pgagroal/Chart.yaml" \
    "appVersion: .*" \
    "appVersion: \"${TARGET_VERSION}\"" \
    "appVersion → ${TARGET_VERSION}"

# values.yaml: replace only the first tag: line (inside image: block)
if [[ "${DRY_RUN}" = true ]]; then
    current_tag=$(grep -n 'tag:' helm/pgagroal/values.yaml | head -1)
    info "[dry-run] helm/pgagroal/values.yaml: image.tag → ${TARGET_VERSION}"
    info "  current: ${current_tag}"
    info "  new:     tag: \"${TARGET_VERSION}\""
else
    # Replace the first occurrence of tag: "..." (portable: use awk for first-match)
    awk -v new="  tag: \"${TARGET_VERSION}\"" '
        !done && /^  tag: "/ { print new; done=1; next } { print }
    ' helm/pgagroal/values.yaml > helm/pgagroal/values.yaml.tmp \
        && mv helm/pgagroal/values.yaml.tmp helm/pgagroal/values.yaml
    info "helm/pgagroal/values.yaml: image.tag → ${TARGET_VERSION}"
fi

# ── optional changelog update ─────────────────────────────────────────────────

if [[ "${UPDATE_CHANGELOG}" = true ]]; then
    step "Updating CHANGELOG.md"
    if [[ "${DRY_RUN}" = true ]]; then
        info "[dry-run] would prepend [Unreleased] section"
        info "  Bump pgagroal from ${CURRENT_VERSION} to ${TARGET_VERSION}"
    else
        changelog_entry="## [Unreleased]

### Changed

- Bump pgagroal from ${CURRENT_VERSION} to ${TARGET_VERSION}

"
        # Prepend after the header lines (line 1-6 are title + format note)
        tmp_cl=$(mktemp)
        head -6 "${CHANGELOG}" > "${tmp_cl}"
        printf '\n%s' "${changelog_entry}" >> "${tmp_cl}"
        tail -n +7 "${CHANGELOG}" >> "${tmp_cl}"
        mv "${tmp_cl}" "${CHANGELOG}"
        info "CHANGELOG.md: prepended [Unreleased] entry"
    fi
fi

# ── dry-run exits here ────────────────────────────────────────────────────────

if [[ "${DRY_RUN}" = true ]]; then
    echo ""
    echo "=== [DRY RUN] Release Summary ==="
    echo "  Previous version : ${CURRENT_VERSION}"
    echo "  New version      : ${TARGET_VERSION}"
    echo "  Files modified   : (none — dry run)"
    echo "  Build            : skipped"
    echo "  Tests            : skipped"
    echo "  Status           : SUCCESS (dry run)"
    exit 0
fi

# ── build ─────────────────────────────────────────────────────────────────────

step "Building container image pgagroal:${TARGET_VERSION}"
if ! docker build -t "pgagroal:${TARGET_VERSION}" .; then
    echo ""
    echo "FAIL: docker build failed for version ${TARGET_VERSION}"
    recovery_hint
    exit 1
fi
BUILD_RESULT="pass"
info "image pgagroal:${TARGET_VERSION} built"

# ── tests ─────────────────────────────────────────────────────────────────────

TEST_RESULT="skip"
if [[ "${SKIP_TESTS}" = false ]]; then
    step "Running integration test"
    if ! bash test/container-start-test.sh; then
        echo ""
        echo "FAIL: integration test failed"
        recovery_hint
        exit 1
    fi

    step "Running backend restart test"
    if ! bash test/backend-restart-test.sh; then
        echo ""
        echo "FAIL: backend restart test failed"
        recovery_hint
        exit 1
    fi
    TEST_RESULT="pass"
else
    step "Tests skipped (--skip-tests)"
fi

# ── summary ───────────────────────────────────────────────────────────────────

modified_files=("${TARGETS[@]}")
if [[ "${UPDATE_CHANGELOG}" = true ]]; then
    modified_files+=("${CHANGELOG}")
fi

echo ""
echo "=== Release Summary ==="
echo "  Previous version : ${CURRENT_VERSION}"
echo "  New version      : ${TARGET_VERSION}"
echo "  Files modified   : ${modified_files[*]}"
echo "  Build            : ${BUILD_RESULT}"
echo "  Tests            : ${TEST_RESULT}"
echo "  Status           : SUCCESS"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff"
echo "  2. Commit: git add ${modified_files[*]} && git commit -m 'Bump pgagroal to ${TARGET_VERSION}'"
echo "  3. Tag and push per docs/release-checklist.md"
