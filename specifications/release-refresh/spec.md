# Specification: pgagroal Upstream Version Refresh

Status: ACTIVE

## Purpose

Provide a repeatable, scriptable workflow for updating the bundled pgagroal
upstream version in this repository. The script is intended to be run manually
once per month (or on demand) to produce a validated build against a newer
pgagroal release.

## Inputs

| Input | Source | Required | Default |
|---|---|---|---|
| Target pgagroal version | `--version <x.y.z>` CLI argument | Yes | none |
| Dry-run mode | `--dry-run` flag | No | false |
| Skip tests | `--skip-tests` flag | No | false |
| Update changelog | `--update-changelog` flag | No | false |

### Version format

The target version must match the regex `^[0-9]+\.[0-9]+\.[0-9]+$` (e.g.
`2.1.0`). No `v` prefix. No pre-release suffixes.

## Outputs

On success the script:

1. Modifies these files with the new upstream version:
   - `Dockerfile` — `ARG PGAGROAL_VERSION=<version>`
   - `Makefile` — `IMAGE_TAG := <version>`
   - `helm/pgagroal/Chart.yaml` — `appVersion: "<version>"`
   - `helm/pgagroal/values.yaml` — `tag: "<version>"`

2. Optionally prepends an `## [Unreleased]` template to `CHANGELOG.md`.

3. Rebuilds the container image tagged `pgagroal:<version>`.

4. Runs the stable test suite (`make test` and `make test-backend-restart`).

5. Prints a final release summary to stdout.

6. Exits 0.

On failure the script:

1. Prints a clear error message identifying the failed step.
2. Exits non-zero (exit code 1).
3. Does NOT revert partial file modifications automatically — the operator
   uses `git checkout -- .` to restore. This is documented in the failure
   output.

In dry-run mode the script:

1. Prints every file modification it would make, without writing.
2. Skips build and test.
3. Prints the release summary with `[DRY RUN]` prefix.
4. Exits 0.

## Invariants

1. The script never modifies files outside the four listed targets (plus
   optionally CHANGELOG.md).
2. The script never creates git commits or tags.
3. The script never pushes to any remote.
4. The script is idempotent: running it twice with the same version produces
   the same file state.
5. The version string appears in each target file in exactly one location,
   matched by a deterministic pattern.

## Preconditions

Before the script begins work, it validates:

| # | Precondition | Failure behavior |
|---|---|---|
| P1 | `--version` argument is present and matches format | Exit 1 with usage message |
| P2 | Required tools are available: `docker`, `git`, `sed`, `grep` | Exit 1 listing missing tools |
| P3 | Working directory is the repository root (contains `Dockerfile`) | Exit 1 |
| P4 | Git working tree is clean (no staged or unstaged changes) | Exit 1 with `git status` output. Skipped in dry-run mode. |

## Postconditions

After a successful non-dry-run execution:

| # | Postcondition |
|---|---|
| Q1 | `grep 'ARG PGAGROAL_VERSION=' Dockerfile` returns the new version |
| Q2 | `grep 'IMAGE_TAG' Makefile` returns the new version |
| Q3 | `grep 'appVersion' helm/pgagroal/Chart.yaml` returns the new version |
| Q4 | `grep 'tag:' helm/pgagroal/values.yaml` (first occurrence) returns the new version |
| Q5 | A container image `pgagroal:<version>` exists locally |
| Q6 | The integration test passed (exit 0) |
| Q7 | The backend restart test passed (exit 0) |

When `--skip-tests` is used, Q5 is still required but Q6 and Q7 are skipped.

## Processing steps (deterministic order)

1. Parse and validate arguments.
2. Check preconditions (P1–P4).
3. Read current version from Dockerfile.
4. Update files: Dockerfile, Makefile, Chart.yaml, values.yaml.
5. Optionally update CHANGELOG.md.
6. Rebuild the container image (`docker build`).
7. Run tests (unless `--skip-tests`).
8. Print release summary.

## Failure conditions

| Step | Failure | Effect |
|---|---|---|
| Argument parsing | Invalid version format | Exit 1, no files touched |
| Preconditions | Missing tool or dirty tree | Exit 1, no files touched |
| File update | sed pattern not found in target | Exit 1, partial modifications may exist |
| Docker build | Build fails (e.g. upstream tag does not exist) | Exit 1, files already modified |
| Tests | Any test exits non-zero | Exit 1, image may exist, files modified |

## Rollback / cleanup expectations

The script does NOT perform automatic rollback. On failure it prints:

```
FAIL: <step description>
Files may have been modified. To restore:
  git checkout -- Dockerfile Makefile helm/pgagroal/Chart.yaml helm/pgagroal/values.yaml CHANGELOG.md
```

This is a deliberate design choice: the operator should inspect the failure
before deciding to restore or continue manually.

## Non-goals

- Automatically creating git commits or tags.
- Pushing images to a registry.
- Bumping the project version (`VERSION` file / Chart.yaml `version`).
- Modifying README.md pinned versions table.
- Running the full test suite (only stable CI tests are run).
