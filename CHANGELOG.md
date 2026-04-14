# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
  SIGKILL-then-start regression and verifies recovery.

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
