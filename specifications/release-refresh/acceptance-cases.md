# Acceptance Cases: pgagroal Upstream Version Refresh

Derived from `spec.md`. Each case maps to a precondition, postcondition,
or failure condition in the specification.

## AC-01: Successful refresh to a valid version

**Given**: clean git working tree, Docker available, valid version `2.1.0`
**When**: `scripts/refresh-pgagroal.sh --version 2.1.0 --skip-tests`
**Then**:
- Exit code 0
- `Dockerfile` contains `ARG PGAGROAL_VERSION=2.1.0`
- `Makefile` contains `IMAGE_TAG    := 2.1.0`
- `Chart.yaml` contains `appVersion: "2.1.0"`
- `values.yaml` first `tag:` line contains `"2.1.0"`
- Summary output includes `Version: 2.1.0` and `Status: SUCCESS`

## AC-02: Invalid version format — missing component

**Given**: any state
**When**: `scripts/refresh-pgagroal.sh --version 2.1`
**Then**:
- Exit code 1
- stderr contains "invalid version format"
- No files modified

## AC-03: Invalid version format — v prefix

**Given**: any state
**When**: `scripts/refresh-pgagroal.sh --version v2.1.0`
**Then**:
- Exit code 1
- stderr contains "invalid version format"
- No files modified

## AC-04: Invalid version format — pre-release suffix

**Given**: any state
**When**: `scripts/refresh-pgagroal.sh --version 2.1.0-rc1`
**Then**:
- Exit code 1
- stderr contains "invalid version format"
- No files modified

## AC-05: Missing --version argument

**Given**: any state
**When**: `scripts/refresh-pgagroal.sh`
**Then**:
- Exit code 1
- stderr contains "Usage:"

## AC-06: Upstream source unavailable (build failure)

**Given**: clean git tree, files updated to version `99.99.99`
**When**: `scripts/refresh-pgagroal.sh --version 99.99.99`
**Then**:
- Exit code 1
- Output contains "FAIL" and mentions the build step
- Output contains the `git checkout` recovery hint
- Files are modified (no automatic rollback)

## AC-07: Test failure

**Given**: build succeeds but test exits non-zero
**When**: (cannot reliably trigger in isolation; verified by code inspection)
**Then**:
- Exit code 1
- Output contains "FAIL" and mentions the test step
- Image may exist locally
- Files are modified

## AC-08: Dirty git working tree

**Given**: uncommitted changes in the working tree
**When**: `scripts/refresh-pgagroal.sh --version 2.1.0`
**Then**:
- Exit code 1
- stderr contains "dirty" or "uncommitted"
- No files modified

## AC-09: Dirty git working tree — dry-run allowed

**Given**: uncommitted changes in the working tree
**When**: `scripts/refresh-pgagroal.sh --version 2.1.0 --dry-run`
**Then**:
- Exit code 0
- Output includes `[DRY RUN]`
- No files modified

## AC-10: Dry-run mode — output correctness

**Given**: clean git tree, current version 2.0.2
**When**: `scripts/refresh-pgagroal.sh --version 2.1.0 --dry-run`
**Then**:
- Exit code 0
- Output shows each file that would be modified
- Output shows the old value → new value for each
- Output includes `[DRY RUN]` in the summary
- No files modified (verified by `git diff` is empty)

## AC-11: Idempotency

**Given**: version already set to 2.0.2
**When**: `scripts/refresh-pgagroal.sh --version 2.0.2 --skip-tests`
**Then**:
- Exit code 0
- All files contain 2.0.2 (unchanged)
- Summary shows `Version: 2.0.2`

## AC-12: --update-changelog flag

**Given**: clean git tree, CHANGELOG.md exists
**When**: `scripts/refresh-pgagroal.sh --version 2.1.0 --skip-tests --update-changelog`
**Then**:
- Exit code 0
- `CHANGELOG.md` starts with `## [Unreleased]` section containing
  `Bump pgagroal from <old> to 2.1.0`
- Previous changelog content is preserved below

## AC-13: --help flag

**Given**: any state
**When**: `scripts/refresh-pgagroal.sh --help`
**Then**:
- Exit code 0
- Prints usage, options, and examples

## AC-14: Summary output format

**Given**: successful refresh
**When**: script completes
**Then**: summary includes at minimum:
- Previous version
- New version
- Files modified (list)
- Build result (pass/skip)
- Test result (pass/skip)
- Status line (SUCCESS or FAIL)

## AC-15: Required tools missing

**Given**: `docker` not in PATH
**When**: `scripts/refresh-pgagroal.sh --version 2.1.0`
**Then**:
- Exit code 1
- stderr lists "docker" as missing
- No files modified

## AC-16: Wrong working directory

**Given**: script run from a directory without `Dockerfile`
**When**: `scripts/refresh-pgagroal.sh --version 2.1.0`
**Then**:
- Exit code 1
- stderr mentions "repository root"
- No files modified
