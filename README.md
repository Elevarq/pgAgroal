# pgAgroal

Production-grade Docker container and Helm chart for [pgagroal](https://github.com/pgagroal/pgagroal) -- a high-performance PostgreSQL connection pooler.

From [Elevarq](https://elevarq.com) — PostgreSQL tools for engineering teams.

[![CI](https://github.com/Elevarq/pgAgroal/actions/workflows/container-ci.yml/badge.svg)](https://github.com/Elevarq/pgAgroal/actions/workflows/container-ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](LICENSE)

## Contents

- pgagroal 2.1.0
- Base image: debian:bookworm-20260316-slim
- Architectures: amd64, arm64

## What this is

A ready-to-deploy packaging of pgagroal that builds from source, runs as a non-root container, and deploys to Kubernetes via Helm. Designed for AWS EKS with RDS backends, but works anywhere Docker or Kubernetes runs.

## Features

- Multi-stage Dockerfile building pgagroal from source (pinned versions, reproducible)
- Helm chart with PDB, security contexts, probes, and Prometheus metrics
- Non-root runtime (UID 1000), all capabilities dropped, seccomp enforced, read-only root filesystem
- Configuration via environment variables -- no config files to mount
- Automated test suite: integration, resilience, pooling validation, failure modes
- CI pipeline: hadolint, ShellCheck, Helm lint, integration and resilience tests
- Scripted monthly upstream refresh workflow with dry-run support

## Quick Start

### Docker

```bash
make run
psql -h localhost -p 6432 -U testuser -d testdb -c 'SELECT 1;'
make stop
```

### Integration stack (pgagroal + pgexporter)

`docker-compose.yml` composes a production-like stack: a PostgreSQL
backend, pgagroal pooling in front of it, and
[pgexporter](https://github.com/pgexporter/pgexporter) exporting
PostgreSQL metrics. It is an integration *example* — the focused
single-component containers live upstream; this repository wires them
together with hardened defaults.

```bash
docker compose up -d --build
# Pooled client traffic (data path):
psql -h localhost -p 6432 -U testuser -d testdb -c 'SELECT 1;'
# PostgreSQL server metrics (pgexporter, direct to the backend):
curl -s http://localhost:5002/metrics | grep '^pgexporter_pg_' | head
# Pooler metrics (pgagroal native endpoint):
curl -s http://localhost:2346/metrics | grep '^pgagroal_' | head
docker compose down -v
```

The stack separates the data path from observability, and uses one
metrics source per layer:

| Path | Component | Endpoint | Connects |
|------|-----------|----------|----------|
| Client data | pgagroal | `:6432` | → postgres |
| Pooler metrics | pgagroal native | `:2346/metrics` | (self) |
| Server metrics | pgexporter | `:5002/metrics` | → postgres **directly** |

pgexporter connects **directly to PostgreSQL**, never through pgagroal,
so the pooler's statistics are not polluted by scrape traffic, and it
authenticates with a least-privilege `pg_monitor` role (created by
`postgres-init/01-pgexporter-role.sql`). See
`specifications/compose-pgexporter-integration/` for the full
specification.

### Kubernetes / Helm

Each release publishes the chart as an OCI artifact to GHCR, so you can
install by reference without a repo checkout (the chart version matches
the release version):

```bash
helm install pgagroal oci://ghcr.io/elevarq/charts/pgagroal \
  --version 1.2.0 \
  --set postgresql.host=my-postgres \
  --set credentials.username=app \
  --set credentials.password=secret \
  -n pgagroal --create-namespace
```

The published chart is cosign-signed (keyless, GitHub OIDC) -- the same
trust root as the container image. Verify before install:

```bash
cosign verify ghcr.io/elevarq/charts/pgagroal:1.2.0 \
  --certificate-identity-regexp='https://github.com/Elevarq/' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com'
```

Or install from a working-tree checkout:

```bash
make build
helm install pgagroal helm/pgagroal/ \
  --set postgresql.host=my-postgres \
  --set credentials.username=app \
  --set credentials.password=secret \
  -n pgagroal --create-namespace
```

#### NetworkPolicy (recommended for production)

The pooler fronts your database and is a high-value lateral-movement
target. The chart ships an opt-in `NetworkPolicy` that restricts ingress
to the client pods that actually need the pooler and egress to just the
backend Postgres and DNS. It is **off by default** (not every CNI enforces
NetworkPolicy, so an always-on manifest would be a silent no-op) — enable
it explicitly:

```bash
helm upgrade pgagroal helm/pgagroal/ \
  --set networkPolicy.enabled=true \
  --set 'networkPolicy.ingressPodSelectors[0].app\.kubernetes\.io/name=my-app' \
  --set 'networkPolicy.egress.backendCIDRs[0]=10.0.5.10/32'
```

| Value | Purpose |
|---|---|
| `networkPolicy.enabled` | Render the policy. Recommended `true` in production. |
| `networkPolicy.ingressPodSelectors` | Label maps of pods allowed to reach the pooler. **Empty = no ingress** (conservative default). |
| `networkPolicy.ingressNamespaceSelectors` | Label maps of namespaces allowed, in addition to pods. |
| `networkPolicy.egress.backendCIDRs` | Backend Postgres CIDR(s) (e.g. an RDS `/32`, or the in-cluster pod-network CIDR). Required for a working policy. |
| `networkPolicy.egress.kubeDNS` | Kube-DNS resolver CIDR(s). |

If you enable the policy with empty ingress selectors or backend CIDRs the
install NOTES warn you, since the pooler would otherwise be unreachable or
unable to reach Postgres.

## Deployment

| Guide | Description |
|---|---|
| [First client deployment](docs/deployment/first-client-deployment.md) | Step-by-step EKS install with acceptance checklist |
| [Post-deployment verification](docs/deployment/post-deployment-verification.md) | 8-step verification and handoff procedure |
| [EKS infrastructure reference](docs/deployment/eks-deployment.md) | ECR, IRSA, Security Groups, monitoring |

Example values files:

```bash
helm/pgagroal/values-client-minimal.yaml   # 3 fields: image, RDS host, secret
helm/pgagroal/values-client-example.yaml   # Full template with CHANGEME markers
helm/pgagroal/values-eks-example.yaml      # Production EKS with AZ anti-affinity
```

## Operations

| Guide | Description |
|---|---|
| [Operations](docs/operations/operations.md) | Startup sequence, probes, scaling, troubleshooting |
| [Failure modes](docs/operations/failure-modes.md) | 9 failure scenarios with recovery paths |
| [Secret rotation](docs/operations/secret-rotation-procedure.md) | Credential rotation for Docker and K8s |

**Production defaults**: `ev_backend = epoll` (avoids upstream io_uring segfault), rolling restart for all config changes (reload is unsafe), `pgagroal-cli ping` checks daemon only (not backend). See [operations guide](docs/operations/operations.md) for details.

## Testing

```bash
make test                  # integration (CI)
make test-backend-restart  # resilience (CI)
make test-concurrent       # concurrent load
make test-pooling          # pool behavior validation
make test-startup-failure  # startup failure mode (CI)
make test-invalid-creds    # credential error handling
make test-all              # everything
make security              # local security, Helm, SBOM, and vulnerability gate
```

## Configuration

| Variable / Helm value | Default | Description |
|---|---|---|
| `PGAGROAL_HOST` / `pgagroal.host` | `*` | Bind address |
| `PGAGROAL_PORT` / `pgagroal.port` | `6432` | Bind port |
| `PG_BACKEND_HOST` / `postgresql.host` | `postgres` | PostgreSQL host |
| `PG_BACKEND_PORT` / `postgresql.port` | `5432` | PostgreSQL port |
| `MAX_CONNECTIONS` / `pgagroal.maxConnections` | `100` | Maximum pool connections |
| `PGAGROAL_LOG_LEVEL` / `pgagroal.logLevel` | `info` | Log level |

## Upstream Refresh

Update the bundled pgagroal version:

```bash
make refresh-dry-run VERSION=2.1.0   # preview
make refresh VERSION=2.1.0           # update, build, test
```

Guide: [docs/release/monthly-refresh.md](docs/release/monthly-refresh.md) | Spec: [specifications/release-refresh/spec.md](specifications/release-refresh/spec.md)

## Release

```bash
make prepare-release   # check consistency, print tag/push commands
make release-check     # non-interactive consistency check
```

Guide: [docs/release/release-process.md](docs/release/release-process.md) | Checklist: [docs/release/release-checklist.md](docs/release/release-checklist.md)

## Image Verification

Published images are built by GitHub Actions from this repository and
pushed to Docker Hub as multi-arch manifests (`linux/amd64`,
`linux/arm64`). Each image includes:

- **SBOM** attestation (build-time software bill of materials)
- **Provenance** attestation (SLSA, `mode=max`)
- **Cosign signature** (keyless, via GitHub OIDC)

Verify a signature before deployment:

```bash
cosign verify elevarq/pgagroal:latest \
  --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

Inspect attestations:

```bash
docker buildx imagetools inspect elevarq/pgagroal:latest
```

### Kubernetes and Helm

In production, pin a version tag rather than `latest`:

```yaml
image:
  repository: elevarq/pgagroal
  tag: "1.2.0"
  pullPolicy: IfNotPresent
```

Verify the pinned image before rolling out:

```bash
cosign verify elevarq/pgagroal:1.2.0 \
  --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

Cosign verification confirms the image was signed by the Elevarq GitHub
Actions workflow. SBOM and provenance attestations provide additional
supply-chain metadata for audit and compliance.

Clusters that enforce image trust can require valid Cosign signatures at
admission time using tools such as
[Sigstore Policy Controller](https://docs.sigstore.dev/policy-controller/overview/)
or [Kyverno](https://kyverno.io/).

## Project Structure

```
├── Dockerfile, entrypoint.sh, *.template    Container build
├── docker-compose.yml                       Local dev stack
├── Makefile                                 All targets
├── helm/pgagroal/                           Helm chart + values examples
├── test/
│   ├── integration/                         Connectivity tests
│   ├── resilience/                          Restart, concurrent, startup failure
│   ├── validation/                          Pooling, credentials
│   └── refresh/                             Refresh script tests
├── scripts/                                 Refresh and release tooling
├── docs/
│   ├── deployment/                          Install, verify, EKS
│   ├── operations/                          Ops guide, failure modes, secrets
│   └── release/                             Process, checklist, refresh, GitHub
├── specifications/                          STDD specs
└── VERSION, CHANGELOG.md, LICENSE           Metadata
```

## Roadmap

- Prometheus metrics validation and Grafana dashboard template
- Elevarq observability sidecar integration (chart stub exists)
- TLS termination configuration guide

## Pinned Versions

| Component | Version |
|---|---|
| Project | 1.2.0 |
| pgagroal | 2.1.0 |
| Debian base | bookworm-20260316-slim |
| PostgreSQL (compose) | 17.4-bookworm |
| Helm chart | 1.2.0 |

## Related

- [Elevarq](https://elevarq.com) — PostgreSQL tools for engineering teams
- [Project page on elevarq.com](https://elevarq.com/products/pgagroal) —
  documentation, examples, and support contracts
- [Arq-Signals](https://github.com/Elevarq/Arq-Signals) — open-source
  PostgreSQL telemetry collector
- [Upstream pgagroal](https://agroal.github.io/pgagroal/) — the connection
  pooler this container packages

## License

[BSD-3-Clause](LICENSE)
