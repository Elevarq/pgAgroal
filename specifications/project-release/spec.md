# Specification: Project Release

Status: ACTIVE

## Purpose

Define the end-to-end workflow for cutting a release of the **container project
itself** — the artifact tracked by `VERSION`, published as
`elevarq/pgagroal:<X.Y.Z>` to Docker Hub, and tagged as `v<X.Y.Z>` on
`Elevarq/pgAgroal`.

This specification governs the *packaging* release. It does **not** govern the
upstream pgagroal version bump (that is `specifications/release-refresh/`),
nor the downstream fan-out to the website and blog (those are separate
concerns).

The two specs compose:

```
release-refresh  →  project-release  →  (downstream surfaces)
upstream bump       packaging tag        website / blog / Docker Hub overview
```

## Inputs

| Input | Source | Required | Default |
|---|---|---|---|
| Target project version | `VERSION` file content | Yes | none |
| Release channel | `stable` (e.g. `1.1.0`) or `rc` (e.g. `1.1.0-rc1`) | Yes | `stable` |
| Pinned pgagroal version | `Dockerfile` `ARG PGAGROAL_VERSION` | Yes | inherited from `release-refresh` |

### Version format

- Stable: `^[0-9]+\.[0-9]+\.[0-9]+$` (e.g. `1.1.0`)
- RC: `^[0-9]+\.[0-9]+\.[0-9]+-rc[0-9]+$` (e.g. `1.1.0-rc1`)

The git tag is always the version with a `v` prefix: `v1.1.0`, `v1.1.0-rc1`.

### Release class

A release belongs to exactly one class, declared **explicitly** as the first
non-blank line under the version heading in `CHANGELOG.md`:

```
## [1.1.0] - 2026-04-29

Class: breaking-config

### Migration
...
```

The `Class:` field is required for every dated changelog section. Valid
values and their extra requirements:

| Class | Trigger | Extra requirement |
|---|---|---|
| `feature` | New functionality, no breaking change | none |
| `fix` | Bug fix only | none |
| `security` | Security fix or hardening | `### Security` subsection in changelog |
| `breaking-config` | Operator-visible config or data migration required | `docs/operations/migrations/<version>.md` exists |

The class is read from the explicit field — never inferred from
subsection structure. This makes the release intent unambiguous at a
glance and gives Gate F a single deterministic field to validate.

## Outputs

On success a project release produces:

1. A signed git tag `v<X.Y.Z>` on `main` of `Elevarq/pgAgroal`.
2. A multi-arch container image at `elevarq/pgagroal:<X.Y.Z>` covering
   `linux/amd64` and `linux/arm64`.
3. Image tags on Docker Hub (per `docs/release/release-checklist.md`):
   - Stable: `<X.Y.Z>`, `<X.Y>`, `latest`
   - RC: `<X.Y.Z>-rc<N>` only — must not update `<X.Y>` or `latest`
4. A cosign keyless signature on the published image (GitHub OIDC issuer).
5. An SBOM attestation (SPDX-JSON) attached to the image.
6. A SLSA provenance attestation (`mode=max`) attached to the image.
7. A GitHub Release object for the tag, with body sourced from the
   corresponding `CHANGELOG.md` section.
8. An updated Docker Hub repository overview rendered from `DOCKER_HUB.md`
   (via `.github/workflows/dockerhub-description.yml`).

## Invariants

1. The project version appears identically in three locations:
   - `VERSION` (entire file content)
   - `helm/pgagroal/Chart.yaml` `version:`
   - The git tag, with a `v` prefix
2. The pinned pgagroal version appears identically in four locations
   (already enforced by `release-refresh`):
   - `Dockerfile` `ARG PGAGROAL_VERSION`
   - `Makefile` `IMAGE_TAG`
   - `helm/pgagroal/Chart.yaml` `appVersion`
   - `helm/pgagroal/values.yaml` `image.tag`
3. The `CHANGELOG.md` contains a section `## [<X.Y.Z>] - <YYYY-MM-DD>` that
   matches the release version and is dated to the release day (UTC).
4. No image is published to Docker Hub outside of `.github/workflows/publish.yml`.
5. A given git tag always produces the same image content modulo base image
   layer updates (reproducibility per parent CLAUDE.md).
6. RC tags never alias to `<X.Y>` or `latest`.
7. The `<X.Y>` and `latest` aliases on Docker Hub always point to a `stable`
   tag of the corresponding line.

## Preconditions (release gates)

The six gates from the parent CLAUDE.md `Release Protocol`, applied to a
project release. All gates are mandatory; failure of any gate halts the
release.

### Gate A — Correctness

| # | Check | Tool / target |
|---|---|---|
| A1 | Unit + integration tests pass against the **built artifact** | `make test-all` |
| A2 | Docker-restart resilience test passes | `make test-docker-restart` |
| A3 | Backend-restart resilience test passes | `make test-backend-restart` |
| A4 | Startup-failure test passes | `make test-startup-failure` |
| A5 | Helm chart renders | `make helm-template` |

### Gate B — Lint / Quality

| # | Check | Tool |
|---|---|---|
| B1 | Dockerfile lint | `hadolint Dockerfile` |
| B2 | GitHub Actions lint | `actionlint` |
| B3 | Helm chart lint | `make helm-lint` (i.e. `helm lint`) |
| B4 | Shell script lint (entrypoint, scripts/) | `shellcheck` (where present) |
| B5 | YAML lint on configs and chart values | `yamllint` |

### Gate C — Security

| # | Check | Tool | Severity rule |
|---|---|---|---|
| C1 | Filesystem vuln + secret scan | `trivy fs --scanners vuln,secret .` | CRITICAL → STOP; HIGH → fix or document |
| C2 | Config / IaC scan | `trivy config .` | same |
| C3 | Image scan against the built artifact | `trivy image pgagroal:<pgagroal-ver>` | same |
| C4 | Full-history secret scan | `gitleaks detect --source .` | any finding → STOP |

### Gate D — Supply Chain

| # | Check |
|---|---|
| D1 | `Dockerfile` base images pinned to a specific tag (no `:latest`) |
| D2 | All GitHub Actions in `.github/workflows/` pinned to a major version tag (`@vN`) at minimum |
| D3 | Working tree is clean — no uncommitted changes when the tag is created |
| D4 | `go.sum` / lock files (where applicable) committed and matching |
| D5 | No vendored secrets or credentials in the repository |

### Gate E — Artifact

| # | Check |
|---|---|
| E1 | Multi-arch image builds (`linux/amd64`, `linux/arm64`) |
| E2 | SBOM generated (`syft` or build-attestation) |
| E3 | SLSA provenance generated (`mode=max`) |
| E4 | Cosign signature applied (keyless, GitHub OIDC) |

### Gate F — Release Hygiene

| # | Check |
|---|---|
| F1 | `VERSION` matches `Chart.yaml` `version` matches the proposed tag |
| F2 | pgagroal version consistency holds (Invariant #2) |
| F3 | `CHANGELOG.md` has a dated section for the release version (Invariant #3) |
| F4 | The dated section contains a `Class:` field with a valid value (`feature`, `fix`, `security`, `breaking-config`) |
| F5 | If `Class: breaking-config`: `docs/operations/migrations/<version>.md` exists |
| F6 | If `Class: security`: `### Security` subsection present in changelog |
| F7 | `README.md` "Pinned versions" table reflects current pinned versions |
| F8 | `DOCKER_HUB.md` quick-start and verification snippets reference the release version |

`make prepare-release` runs F1–F2 today. F3–F8 are added by this spec.

## Postconditions

After the publish workflow completes for a `v<X.Y.Z>` push:

| # | Postcondition | How to verify |
|---|---|---|
| Q1 | Publish workflow run for the tag exists and exited 0 | `gh run list --workflow publish.yml` |
| Q2 | Image `elevarq/pgagroal:<X.Y.Z>` exists on Docker Hub with a multi-arch index | `docker buildx imagetools inspect elevarq/pgagroal:<X.Y.Z>` |
| Q3 | For stable releases: `<X.Y>` and `latest` aliases point to the same digest as `<X.Y.Z>` | `docker buildx imagetools inspect` of each |
| Q4 | For RC releases: `<X.Y>` and `latest` are unchanged from the previous stable | digest comparison |
| Q5 | Cosign signature verifies | `cosign verify elevarq/pgagroal:<X.Y.Z> --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" --certificate-oidc-issuer "https://token.actions.githubusercontent.com"` |
| Q6 | SBOM attestation present | `cosign download attestation --predicate-type https://spdx.dev/Document elevarq/pgagroal:<X.Y.Z>` |
| Q7 | SLSA provenance attestation present | `cosign download attestation --predicate-type https://slsa.dev/provenance/v1 elevarq/pgagroal:<X.Y.Z>` |
| Q8 | GitHub Release object exists with the changelog body | `gh release view v<X.Y.Z>` |
| Q9 | Docker Hub overview matches `DOCKER_HUB.md` of the tagged commit | manual check on hub.docker.com |

## Processing steps (deterministic order)

A project release executes as a sequence of three phases. Each phase has a
clear human / automation handoff.

### Phase 1 — Preparation (human-driven, on a feature branch)

1. Confirm the upstream refresh has landed (per `release-refresh` spec).
2. Edit `VERSION` to the new project version.
3. Edit `helm/pgagroal/Chart.yaml` `version:` to match.
4. Edit `CHANGELOG.md`: convert `## [Unreleased]` to `## [<X.Y.Z>] - <date>`,
   add a `Class: <feature|fix|security|breaking-config>` line as the first
   non-blank line under the heading, and add the appropriate subsections.
5. Edit `README.md` "Pinned versions" table.
6. Edit `DOCKER_HUB.md` quick-start and verification snippets.
7. If `Class: breaking-config`: author `docs/operations/migrations/<version>.md`.
8. Run `make prepare-release` and resolve any reported issue.
9. Open a PR, get it merged to `main` through normal review.

### Phase 2 — Tag and publish (automation-driven)

10. From `main` at the merge commit, create and push the annotated tag:
    ```
    git tag -a v<X.Y.Z> -m "Release v<X.Y.Z> (pgagroal <pgagroal-ver>)"
    git push origin v<X.Y.Z>
    ```
11. `.github/workflows/publish.yml` runs all six release gates, builds
    multi-arch, generates SBOM + provenance, signs with cosign, pushes to
    Docker Hub, and creates the GitHub Release. (Today the workflow runs
    Gates A, C, E. Gates B, D, F are extended by this spec.)
12. `.github/workflows/dockerhub-description.yml` updates the Docker Hub
    overview from `DOCKER_HUB.md`.

### Phase 3 — Post-release verification (human-driven)

13. Verify all postconditions Q1–Q9.
14. Roll out to a non-production environment first; for `breaking-config`
    releases, exercise the migration path before any production use.
15. Announce per `docs/release/release-evidence-checklist.md`.

## Failure conditions

| Phase | Failure | Effect |
|---|---|---|
| Phase 1 | Any Gate F check fails locally | PR cannot merge; fix on the feature branch |
| Phase 1 | `Class:` field missing or invalid in the dated changelog section | F4 fails |
| Phase 1 | `Class: breaking-config` declared but migration doc missing | F5 fails |
| Phase 1 | `Class: security` declared but `### Security` subsection missing | F6 fails |
| Phase 2 | Any of Gates A–F fail in CI | publish workflow exits non-zero; tag remains but no image is published; remediate by deleting the tag (`git push origin :v<X.Y.Z>`), fixing on a new branch, and re-tagging |
| Phase 2 | CRITICAL CVE found by Trivy | STOP per parent CLAUDE.md severity rule |
| Phase 2 | Any gitleaks finding | STOP — secret rotation required before retag |
| Phase 2 | Cosign signing fails (OIDC error) | STOP — image must not be published unsigned; rerun workflow after diagnosing |
| Phase 3 | Cosign verify or attestation download fails for the published image | STOP and investigate before any consumer announcement; treat the image as untrusted until resolved |

## Rollback / cleanup expectations

This spec does NOT define automated rollback of a published image. A
published image is immutable; "rollback" means publishing a follow-up
release that supersedes it.

If a release must be retracted before any consumer adoption:

1. Delete the git tag: `git push origin :v<X.Y.Z>`
2. Delete the Docker Hub tag manually (only if the team consensus is that
   the broken release should not remain accessible; otherwise leave it for
   audit trail).
3. Cut a new release at the next patch level with a `## [<X.Y.Z+1>]`
   changelog entry that explains the retraction.

This is intentionally not automated — retracting a published artifact is a
high-blast-radius decision that requires human judgement.

## Non-goals

- Bumping the upstream pgagroal version (covered by `release-refresh`).
- Updating the marketing website or blog (separate concern, separate
  surface, separate change cadence).
- Mirroring the image to ECR or other private registries (covered by
  `docs/release/release-checklist.md` operational steps, not by this
  spec).
- Authoring release announcements or social posts.
- Dependency bumping (Dependabot / renovate own that).
