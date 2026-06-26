# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-06-26

Class: feature

### Security

- Bump the Debian base-image snapshot `bookworm-20260316-slim` →
  `bookworm-20260623-slim` so the runtime `apt-get upgrade` reaches
  `libssl3 3.0.20-1~deb12u2`, resolving CVE-2026-45447 (HIGH — OpenSSL
  heap use-after-free in `PKCS7_verify()`). The dated snapshot pins apt
  to its date, so the older snapshot could not pull the fix even with
  the existing security-upgrade step. (#60)

### Added

- Integration stack: `docker-compose.yml` now composes pgagroal +
  pgexporter against a PostgreSQL backend, demonstrating two independent
  observability paths — pgexporter for server metrics (direct to the
  backend, never through the pooler) and pgagroal's native endpoint for
  pooler metrics. pgexporter is built from pinned upstream source and
  authenticates with a least-privilege `pg_monitor` role. Adds a
  behavioral specification, acceptance cases, and
  integration/validation/resilience tests wired into CI. (#42)
- Release workflow now publishes the Helm chart as an OCI artifact to
  `oci://ghcr.io/elevarq/charts/pgagroal`, cosign-signed with the same
  keyless GitHub OIDC identity as the container image. The chart version
  is stamped from the release tag at package time. (#40)

### Fixed

- **Helm chart default image now resolves to a published image (#56).**
  `image.repository` defaulted to `pgagroal` (no registry) and `image.tag`
  to `2.1.0` (the appVersion), but the published image is
  `ghcr.io/elevarq/pgagroal:<chart-version>`. The defaults are now
  `repository: ghcr.io/elevarq/pgagroal` and an empty `tag` that falls
  through to the chart version, so a default `helm install` pulls a real
  image. (The chart itself was also missing from ghcr because the
  `publish-chart` job postdated v1.2.0 — fixed by re-cutting a release with
  the job present.)

## [1.2.0] - 2026-05-27

Class: feature

### Added

- GHCR distribution: the multi-arch image is now published to
  `ghcr.io/elevarq/pgagroal` alongside Docker Hub, from the same build,
  with cosign keyless signatures, SBOM, and SLSA provenance on both
  registries.
- Release notes now document full verification — the cosign signature
  plus SBOM and SLSA-provenance `verify-attestation` commands — and link
  the supply-chain verification guide.
- Community-health files: `CODE_OF_CONDUCT.md` and `GOVERNANCE.md`.

### Changed

- `SECURITY.md` names `security@elevarq.com` as the disclosure channel.
- `CODEOWNERS` now references a valid owner (previously a non-existent
  team, so review routing was inert).
- README gains a CI status badge; issue templates migrated to structured
  YAML forms.
- Release tooling: new Gate F9 blocks stale image references in user
  docs; added a local container security gate.

### Security

- Apply Debian security updates in the runtime image so CVE fixes from
  bookworm-security (e.g. libgnutls30 `deb12u7`, libcap2 `deb12u3`) are
  included — the pinned base-image snapshot does not bake these in.

### CI

- Bump `azure/setup-helm` 4 → 5 and `aquasecurity/trivy-action`
  0.35.0 → 0.36.0.

No change to the bundled pgagroal version (2.1.0).

## [1.1.0] - 2026-04-29

Class: breaking-config

### Migration

Upstream pgagroal 2.1.0 introduces breaking changes to the vault
encryption format and the management wire protocol. Operators must
regenerate the master key, delete and re-add all users, and upgrade
the server and every `pgagroal-cli` / `pgagroal-vault` client
together. See [docs/operations/migrations/1.1.0.md](docs/operations/migrations/1.1.0.md)
for the full procedure.

### Changed

- Bump pgagroal from 2.0.2 to 2.1.0 (upstream feature release).
  Highlights: built-in health check, improved failover, Prometheus
  web console, AES-256-GCM vault encryption with per-installation
  salt and 600,000 PBKDF2 iterations, RFC 4013 SASLprep on passwords.
- Helm chart `appVersion` 2.0.2 → 2.1.0
- Helm chart `version` 1.0.1 → 1.1.0
- README, DOCKER_HUB.md image references updated to 1.1.0

### Added

- `docs/operations/migrations/1.1.0.md` — vault re-initialization
  and synchronized client upgrade procedure for operators upgrading
  from 1.0.x.

### Remaining base image CVEs (unfixed upstream)

These advisories were flagged by Trivy on `pgagroal:1.1.0`. None of
the affected libraries are linked by any pgagroal binary (verified
via `ldd` on `pgagroal`, `pgagroal-cli`, and `pgagroal-admin`); they
are present in the image as transitive dependencies of
`postgresql-client` and apt tooling but never loaded into a pgagroal
process.

- CVE-2023-45853 (CRITICAL, zlib, `will_not_fix`) — minizip API only, not used by pgagroal
- CVE-2026-0861 (HIGH, glibc) — no Debian patch available
- CVE-2023-2953 (HIGH, openldap) — no Debian patch available
- CVE-2026-41989 (HIGH, libgcrypt20) — DoS via crafted ECDH; libgcrypt not linked by pgagroal binaries
- CVE-2026-29111 (HIGH, systemd) — IPC-driven RCE; container has no systemd, library not loaded
- CVE-2025-69720 (HIGH, ncurses / libtinfo6) — buffer overflow; not linked by pgagroal binaries

## [1.0.1] - 2026-04-14

Class: fix

### Fixed

- Container now survives `docker restart` (or any stop/start cycle) after
  an ungraceful termination. Upstream pgagroal removes its PID file on
  SIGTERM only; on SIGKILL / OOM / stop-grace expiry the stale
  `/tmp/pgagroal.<port>.pid` was left on the writable layer and blocked
  the next start with `pgagroal: PID file ... exists, is there another
  instance running ?`. The entrypoint now removes any stale PID file
  before exec'ing pgagroal. Spec: `specifications/docker-restart-resilience/`.

### Added

- `make test-docker-restart` — resilience test that reproduces the
  SIGKILL-then-start regression and verifies recovery. Also wired into
  `.github/workflows/container-ci.yml` (PR checks) and the tag-time
  release pipeline.
- Full-history gitleaks secret scan on every pull request
  (`.github/workflows/container-ci.yml`), pinned to gitleaks v8.21.2.

### Changed

- Release workflow (`.github/workflows/publish.yml`) now enforces all
  six release-protocol gates on every `v*` tag push: validate (tag ↔
  VERSION, changelog entry present), test-against-built-artifact
  (integration + backend-restart + docker-restart + startup-failure),
  security (Trivy fs + config + image, gitleaks full-history), then
  the existing multi-arch publish with cosign signing and
  SBOM/provenance attestations. A new `release` job creates the
  GitHub Release with the changelog section and supply-chain metadata.
  Registry, architectures, and signing posture are unchanged.

## [1.0.0] - 2026-04-10

First stable public release. Establishes the 1.x release line.

### Added

- Multi-arch Docker images (linux/amd64, linux/arm64) built and published via GitHub Actions
- Cosign keyless image signing (GitHub OIDC) on every release
- SBOM and SLSA provenance attestations attached at build time
- Automated publish workflow with tag-triggered CI/CD
- Complete public documentation: getting started, configuration, Kubernetes deployment, observability, security, and troubleshooting
- Release evidence checklist and post-release verification procedures
- Docker Hub repository overview managed from DOCKER_HUB.md
- Supply chain security documentation aligned with SOC 2 / ISO 27001 readiness

### Changed

- Release versioning standardized at 1.0.0 (0.2.0-rc1 was transitional while the publish and signing pipeline was stabilized)
- Container runtime hardening: non-root, all capabilities dropped, read-only root filesystem, seccomp RuntimeDefault
- Helm chart version aligned at 1.0.0

### Pinned versions

- pgagroal: 2.0.2
- Debian base: bookworm-20260316-slim
- PostgreSQL (compose): 17.4-bookworm

## [0.2.0] - 2026-03-23

### Changed

- Update Debian base image from bookworm-20250224-slim to bookworm-20260316-slim
  - Resolves 10 CVEs (1 CRITICAL, 9 HIGH) in base OS packages
  - gpgv, glibc, gnutls, xz, pam all patched to latest Debian 12.13 versions
- Add resource limits to Helm initContainer (copy-config-templates)

### Added

- Trivy security scanning in CI (filesystem, image, and config scans)
- .dockerignore to reduce Docker build context
- .trivyignore with narrowly scoped suppressions for advisory-only checks

### Remaining base image CVEs (unfixed upstream)

- CVE-2023-45853 (CRITICAL, zlib, `will_not_fix`) — affects minizip API only, not used by pgagroal
- CVE-2026-0861 (HIGH, glibc) — no Debian patch available
- CVE-2023-2953 (HIGH, openldap) — no Debian patch available

## [0.1.0] - 2026-03-16

Initial release of the pgagroal container project.

### Added

- Multi-stage Dockerfile building pgagroal 2.0.2 from source on Debian bookworm-slim
- Non-root runtime (UID 1000), all capabilities dropped, seccomp RuntimeDefault
- Configuration via environment variables with envsubst templates
- Docker Compose stack with PostgreSQL 17.4 backend and test client
- Helm chart (0.1.0) with:
  - Deployment, Service, ConfigMap, Secret, ServiceAccount, PDB
  - Readiness/liveness probes via `pgagroal-cli ping`
  - Security contexts (readOnlyRootFilesystem, non-root, no capabilities)
  - Optional Prometheus metrics port
  - Observability sidecar stub for future Elevarq integration
  - EKS production example values with AZ anti-affinity and IRSA
- Test suite:
  - Integration test (build, start, health check, psql connectivity)
  - Backend restart resilience test
  - Concurrent connection load test
  - Pooling behavior validation (pg_backend_pid reuse)
  - Startup failure mode test (unreachable backend)
  - Invalid credentials test
- GitHub Actions CI pipeline:
  - hadolint, ShellCheck, Helm lint
  - Docker build with Buildx and GHA cache
  - Integration, resilience, and startup failure tests
- Documentation:
  - EKS deployment guide
  - Operations guide (startup, probes, scaling, troubleshooting)
  - Failure modes reference (7 scenarios documented)
  - Secret rotation procedure
  - Release checklist

### Pinned versions

- pgagroal: 2.0.2
- Debian base: bookworm-20250224-slim
- PostgreSQL (compose): 17.4-bookworm
