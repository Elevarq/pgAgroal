# Monthly Upstream Refresh

How to update the bundled pgagroal version to a newer upstream release.

## When to run

- Once per month, after a new pgagroal stable release
- On demand, if a security fix or critical bug fix is released upstream
- Check releases at: https://github.com/pgagroal/pgagroal/releases

## Prerequisites

- Docker running
- Clean git working tree (`git status` shows no changes)
- Know the target pgagroal version (e.g. `2.1.0`)

## Commands

### Dry run (see what would change, no modifications)

```bash
make refresh-dry-run VERSION=2.1.0
```

### Full refresh (update files, build, test)

```bash
make refresh VERSION=2.1.0
```

### Refresh without tests (faster, for known-good versions)

```bash
scripts/refresh-pgagroal.sh --version 2.1.0 --skip-tests
```

### Refresh with changelog entry

```bash
scripts/refresh-pgagroal.sh --version 2.1.0 --update-changelog
```

## What the script does

1. Validates the version format and checks preconditions
2. Updates four files:
   - `Dockerfile` — `ARG PGAGROAL_VERSION=<version>`
   - `Makefile` — `IMAGE_TAG := <version>`
   - `helm/pgagroal/Chart.yaml` — `appVersion: "<version>"`
   - `helm/pgagroal/values.yaml` — `image.tag: "<version>"`
3. Optionally prepends an `[Unreleased]` section to `CHANGELOG.md`
4. Rebuilds the container image
5. Runs the integration test and backend restart test
6. Prints a release summary

## Expected output (success)

```
=== pgagroal upstream version refresh ===
  Current : 2.0.2
  Target  : 2.1.0

--- Updating version references
  Dockerfile: ARG PGAGROAL_VERSION → 2.1.0
  Makefile: IMAGE_TAG → 2.1.0
  helm/pgagroal/Chart.yaml: appVersion → 2.1.0
  helm/pgagroal/values.yaml: image.tag → 2.1.0
--- Building container image pgagroal:2.1.0
  image pgagroal:2.1.0 built
--- Running integration test
--- Running backend restart test

=== Release Summary ===
  Previous version : 2.0.2
  New version      : 2.1.0
  Files modified   : Dockerfile Makefile helm/pgagroal/Chart.yaml helm/pgagroal/values.yaml
  Build            : pass
  Tests            : pass
  Status           : SUCCESS

Next steps:
  1. Review changes: git diff
  2. Commit: git add ... && git commit -m 'Bump pgagroal to 2.1.0'
  3. Tag and push per docs/release-checklist.md
```

## After the script succeeds

1. Review the diff:
   ```bash
   git diff
   ```

2. Commit the changes:
   ```bash
   git add Dockerfile Makefile helm/pgagroal/Chart.yaml helm/pgagroal/values.yaml
   git commit -m "Bump pgagroal to 2.1.0"
   ```

3. Optionally bump the project version in `VERSION` and `Chart.yaml version`

4. Tag and push per [docs/release-checklist.md](release-checklist.md)

## Failure recovery

If the script fails mid-way (e.g. build failure because the upstream tag does not exist):

```bash
# Inspect the error output (it tells you which step failed)

# Restore all modified files
git checkout -- Dockerfile Makefile helm/pgagroal/Chart.yaml helm/pgagroal/values.yaml CHANGELOG.md

# Verify clean state
git status
```

The script never creates commits or pushes, so there is nothing to revert upstream.

## Testing the script itself

```bash
bash test/refresh/test-refresh.sh
```

This runs automated tests for argument validation, dry-run behavior, version replacement, idempotency, and dirty-tree detection.
