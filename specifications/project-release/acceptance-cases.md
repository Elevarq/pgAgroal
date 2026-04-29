# Acceptance Cases: Project Release

Derived from `spec.md`. Each case maps to an invariant, gate, postcondition,
or failure condition in the specification. Cases are language-neutral; the
implementation may realize them as shell tests, Go tests, GitHub Actions
job assertions, or a mix.

Tags: `[invariant]` `[gate-X]` `[postcondition]` `[failure]`.

## AC-01: Version triple consistency — happy path  `[invariant]`

**Given**: `VERSION` contains `1.1.0`, `Chart.yaml` `version: 1.1.0`,
proposed tag `v1.1.0`
**When**: `make prepare-release` runs
**Then**:
- Exit code 0
- Output reports "VERSION matches Chart.yaml version"
- Output reports "tag v1.1.0 does not exist yet"

## AC-02: Version triple inconsistency — VERSION vs Chart.yaml  `[invariant] [gate-F]`

**Given**: `VERSION` contains `1.1.0`, `Chart.yaml` `version: 1.0.1`
**When**: `make prepare-release` runs
**Then**:
- Exit code non-zero (or warning count > 0 in current implementation)
- Output identifies the mismatch with both values

## AC-03: pgagroal version consistency  `[invariant] [gate-F]`

**Given**: Dockerfile, Makefile, Chart.yaml `appVersion`, values.yaml
`image.tag` all show `2.1.0`
**When**: `make prepare-release` runs
**Then**:
- Exit code 0
- Output reports "pgagroal version consistent across all files (2.1.0)"

## AC-04: pgagroal version drift  `[invariant] [gate-F]`

**Given**: Dockerfile shows `2.1.0` but `values.yaml` `image.tag: "2.0.2"`
**When**: `make prepare-release` runs
**Then**:
- Exit code non-zero
- Output enumerates each file and its detected value

## AC-05: Tag format — stable  `[invariant]`

**Given**: `VERSION` contains `1.1.0`
**When**: the publish workflow runs on tag push `v1.1.0`
**Then**:
- The Docker metadata step produces image tags `1.1.0`, `1.1`, `latest`

## AC-06: Tag format — RC  `[invariant]`

**Given**: `VERSION` contains `1.1.0-rc1`
**When**: the publish workflow runs on tag push `v1.1.0-rc1`
**Then**:
- The Docker metadata step produces image tag `1.1.0-rc1` only
- `1.1` and `latest` aliases on Docker Hub are unchanged from the previous
  stable

## AC-07: Tag format — RC must not promote latest  `[invariant]`

**Given**: previous stable digest D₀ at `latest` and `1.0`
**When**: an RC release `v1.1.0-rc1` is published
**Then**:
- `docker buildx imagetools inspect elevarq/pgagroal:latest` returns digest D₀
- `docker buildx imagetools inspect elevarq/pgagroal:1.0` returns digest D₀

## AC-08: Changelog dated section present  `[gate-F]`

**Given**: `VERSION` is `1.1.0`, today is `2026-04-29`
**When**: a Gate F enforcement script reads `CHANGELOG.md`
**Then**:
- A line matching `^## \[1\.1\.0\] - \d{4}-\d{2}-\d{2}$` exists
- The date is not in the future (UTC)

## AC-09: Changelog missing dated section  `[failure] [gate-F]`

**Given**: `VERSION` is `1.1.0` but `CHANGELOG.md` only contains
`## [Unreleased]`
**When**: Gate F enforcement runs
**Then**:
- Exit code non-zero
- Error message names the missing version

## AC-10: Release class — explicit field present and valid  `[gate-F]`

**Given**: `CHANGELOG.md` section for `1.1.0` contains
`Class: breaking-config` as the first non-blank line under the heading
**When**: Gate F enforcement runs
**Then**:
- F4 passes (field present, value valid)

## AC-10b: Release class — explicit field missing  `[gate-F] [failure]`

**Given**: `CHANGELOG.md` section for `1.1.0` has no `Class:` line
**When**: Gate F enforcement runs
**Then**:
- Exit code non-zero
- Error message cites F4 and names the missing field

## AC-10c: Release class — invalid value  `[gate-F] [failure]`

**Given**: `CHANGELOG.md` section for `1.1.0` contains
`Class: experimental`
**When**: Gate F enforcement runs
**Then**:
- Exit code non-zero
- Error message cites F4 and lists the four valid values

## AC-11: Release class — breaking-config requires migration doc  `[gate-F]`

**Given**: `CHANGELOG.md` section for `1.1.0` contains
`Class: breaking-config`
**When**: Gate F enforcement runs
**Then**:
- F5 passes only if `docs/operations/migrations/1.1.0.md` exists
- If the migration doc is absent, exit code non-zero with a message
  citing F5

## AC-11b: Release class — non-breaking does NOT require migration doc  `[gate-F]`

**Given**: `CHANGELOG.md` section for `1.0.2` contains `Class: fix`,
no migration doc exists
**When**: Gate F enforcement runs
**Then**:
- F5 passes (does not apply when class is not `breaking-config`)

## AC-12: Release class — security requires Security subsection  `[gate-F]`

**Given**: `CHANGELOG.md` section for `1.0.3` contains `Class: security`
**When**: Gate F enforcement runs
**Then**:
- A `### Security` subsection exists under `## [1.0.3] - <date>`
- If absent, exit code non-zero with a message citing F6

## AC-12b: Release class — feature/fix has no extra requirement  `[gate-F]`

**Given**: `CHANGELOG.md` section for `1.0.2` contains `Class: fix`
and only a `### Fixed` subsection
**When**: Gate F enforcement runs
**Then**:
- Exit code 0 (F5 and F6 do not apply)

## AC-13: Working tree clean at tag time  `[gate-D]`

**Given**: `git status` shows uncommitted changes
**When**: an operator attempts to create the release tag
**Then**:
- The release flow halts before tag creation
- (Today this is a manual step; the spec mandates that automation must not
  proceed past this check)

## AC-14: Trivy CRITICAL on built image  `[gate-C] [failure]`

**Given**: `trivy image pgagroal:<pgagroal-ver>` reports a CRITICAL finding
**When**: Gate C runs in the publish workflow
**Then**:
- Workflow exit code non-zero
- Image is not pushed
- The release tag remains but the Docker Hub image is absent

## AC-15: Trivy HIGH with documented justification  `[gate-C]`

**Given**: a HIGH finding exists with no upstream patch and is listed in
`.trivyignore` with a justification comment
**When**: Gate C runs
**Then**:
- Workflow exits 0
- The justification appears in the workflow log (or release evidence)

## AC-16: Gitleaks finding  `[gate-C] [failure]`

**Given**: `gitleaks detect --source .` returns any finding
**When**: Gate C runs
**Then**:
- Workflow exit code non-zero
- Image is not pushed
- The finding must be remediated and the affected secret rotated before
  the tag is re-pushed

## AC-17: Hadolint failure on Dockerfile  `[gate-B] [failure]`

**Given**: `hadolint Dockerfile` returns a violation at error severity
**When**: Gate B runs
**Then**:
- Workflow exit code non-zero
- Image is not pushed

## AC-18: Action pinning  `[gate-D]`

**Given**: every action reference in `.github/workflows/*.yml`
**When**: Gate D runs
**Then**:
- Each `uses:` line references a tag or SHA, not a branch (e.g. not
  `@master`, not `@main`)

## AC-19: Multi-arch manifest  `[postcondition]`

**Given**: a stable release `v1.1.0` has been published
**When**: `docker buildx imagetools inspect elevarq/pgagroal:1.1.0`
**Then**:
- The output includes both `linux/amd64` and `linux/arm64` platforms

## AC-20: Cosign signature verifies  `[postcondition]`

**Given**: a stable release `v1.1.0` has been published
**When**:
```
cosign verify elevarq/pgagroal:1.1.0 \
  --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```
**Then**:
- Exit code 0
- At least one valid signature is reported

## AC-21: SBOM attestation present  `[postcondition]`

**Given**: a stable release `v1.1.0`
**When**: `cosign download attestation --predicate-type https://spdx.dev/Document elevarq/pgagroal:1.1.0`
**Then**:
- Exit code 0
- Output is a valid SPDX-JSON document

## AC-22: SLSA provenance attestation present  `[postcondition]`

**Given**: a stable release `v1.1.0`
**When**: `cosign download attestation --predicate-type https://slsa.dev/provenance/v1 elevarq/pgagroal:1.1.0`
**Then**:
- Exit code 0
- Output validates as SLSA provenance v1

## AC-23: GitHub Release exists with changelog body  `[postcondition]`

**Given**: a tag `v1.1.0` was pushed and the publish workflow completed
**When**: `gh release view v1.1.0 --json body`
**Then**:
- Exit code 0
- The `body` field contains the corresponding `CHANGELOG.md` section text

## AC-24: stable aliases promoted  `[postcondition]`

**Given**: a stable release `v1.1.0` has been published
**When**: digests are inspected
**Then**:
- `elevarq/pgagroal:1.1.0`, `elevarq/pgagroal:1.1`, `elevarq/pgagroal:latest`
  share the same multi-arch index digest

## AC-25: RC aliases not promoted  `[postcondition]`

**Given**: an RC release `v1.1.0-rc1` has been published while latest stable
is `v1.0.1`
**When**: digests are inspected
**Then**:
- `elevarq/pgagroal:1.1.0-rc1` exists
- `elevarq/pgagroal:1.1` does NOT exist (or points elsewhere; it must not
  point at the RC digest)
- `elevarq/pgagroal:latest` still points at the `1.0.1` digest

## AC-26: Idempotent tag — re-pushing the same tag does not republish  `[invariant]`

**Given**: tag `v1.1.0` already exists locally and remote
**When**: an operator runs `git push origin v1.1.0` again
**Then**:
- The push is a no-op (or rejected by branch protection)
- No second publish workflow runs

## AC-27: Retracted tag flow  `[failure]`

**Given**: a tag `v1.1.0` was pushed but the publish workflow failed at
Gate C
**When**: the operator runs `git push origin :v1.1.0`, fixes the issue,
and re-pushes `v1.1.0`
**Then**:
- The publish workflow runs again on the new tag commit
- The image tag `1.1.0` on Docker Hub points at the digest produced by the
  re-run

> Note: this case is acceptable only when no consumer has pulled the
> original failed image. If the original ran far enough to push, the
> spec-mandated flow is a follow-up patch release, not a re-tag.

## AC-28: README pinned-versions reflects current pins  `[gate-F]`

**Given**: `Dockerfile` pins pgagroal `2.1.0`
**When**: Gate F runs
**Then**:
- `README.md` "Pinned versions" table contains `2.1.0`
- (Today this is a manual review item; the spec mandates that automation
  must verify it before tag.)

## AC-29: DOCKER_HUB.md references the release version  `[gate-F]`

**Given**: a release `v1.1.0`
**When**: Gate F runs
**Then**:
- `DOCKER_HUB.md` contains `elevarq/pgagroal:1.1.0` in the quickstart and
  cosign-verify snippets
- `DOCKER_HUB.md` does not contain references to the previous version
  (`1.0.1`) in those snippets

## AC-30: F9 — README + DOCKER_HUB.md only reference current version  `[gate-F]`

**Given**: `VERSION` is `1.1.0`; `README.md` and `DOCKER_HUB.md` contain
`elevarq/pgagroal:1.1.0` references and no other version pins
**When**: Gate F enforcement runs
**Then**:
- F9 passes (no stale references found)

## AC-31: F9 — stale reference in README.md  `[gate-F] [failure]`

**Given**: `VERSION` is `1.1.0`; `README.md` contains
`elevarq/pgagroal:1.0.1` somewhere outside an explicitly-historical
section (e.g. a Helm tag example or a cosign-verify snippet)
**When**: Gate F enforcement runs
**Then**:
- Exit code non-zero
- Error message cites F9
- Error message names the stale version (`1.0.1`) and the file
  (`README.md`)

## AC-32: F9 — stale reference in DOCKER_HUB.md  `[gate-F] [failure]`

**Given**: `VERSION` is `1.1.0`; `DOCKER_HUB.md` contains
`elevarq/pgagroal:1.0.1` (e.g. a leftover row in the "Versioning and
tags" table or an unstaffed example)
**When**: Gate F enforcement runs
**Then**:
- Exit code non-zero
- Error message cites F9
- Error message names the stale version (`1.0.1`) and the file
  (`DOCKER_HUB.md`)

## AC-33: Docker Hub overview synchronized post-release  `[postcondition]`

**Given**: a stable release `v1.1.0` has been published and merged to main
**When**: `.github/workflows/dockerhub-description.yml` completes
**Then**:
- The repo overview on hub.docker.com matches the contents of
  `DOCKER_HUB.md` at the release commit

---

## Coverage map

Every spec rule is referenced by at least one acceptance case. Conversely,
every acceptance case references at least one spec element.

| Spec element | Cases |
|---|---|
| Invariant 1 (project version triple) | AC-01, AC-02 |
| Invariant 2 (pgagroal version quad) | AC-03, AC-04 |
| Invariant 3 (changelog dated) | AC-08, AC-09 |
| Invariant 4 (no manual push) | enforced by repo policy, not testable in isolation |
| Invariant 5 (reproducibility) | implicit — verified by build determinism, future work |
| Invariant 6 (RC never promotes) | AC-06, AC-07, AC-25 |
| Invariant 7 (X.Y / latest point at stable) | AC-24 |
| Gate A | AC-19 (artifact built); rest covered by existing test specs |
| Gate B | AC-17, AC-18 |
| Gate C | AC-14, AC-15, AC-16 |
| Gate D | AC-13, AC-18 |
| Gate E | AC-19, AC-21, AC-22, AC-20 |
| Gate F | AC-01..AC-04, AC-08..AC-12b, AC-28..AC-32 |
| Postconditions Q1–Q9 | AC-19..AC-25, AC-33 |
| Failure: retraction | AC-27 |
| Failure: idempotent push | AC-26 |
