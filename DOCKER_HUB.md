# Elevarq pgAgroal

Production-grade container image for [pgagroal](https://github.com/pgagroal/pgagroal) — a high-performance PostgreSQL connection pooler. Built from source, signed, SBOM-attested, multi-arch. (*Elevarq pgAgroal* is the product; *pgagroal* is the upstream pooler it bundles.)

## Why this image

- **Reproducible builds** from pinned source (pgagroal 2.1.0, Debian bookworm).
- **Multi-arch** manifests: `linux/amd64` and `linux/arm64`.
- **Signed with cosign** (keyless, GitHub OIDC) on every release.
- **SBOM + SLSA provenance** attached as OCI attestations.
- **Hardened runtime**: non-root (UID 1000), all capabilities dropped, read-only root filesystem, seccomp `RuntimeDefault`.
- **Configuration via environment variables** — no config files to mount.
- Aligned with SOC 2 / ISO 27001 engineering practices.

## Quick start

```bash
docker pull elevarq/pgagroal:1.4.1

docker run -d --name pgagroal \
  -p 6432:6432 \
  -e PG_BACKEND_HOST=your-postgres-host \
  -e PG_BACKEND_PORT=5432 \
  elevarq/pgagroal:1.4.1

psql -h localhost -p 6432 -U youruser -d yourdb -c 'SELECT 1;'
```

## Verify

```bash
cosign verify elevarq/pgagroal:1.4.1 \
  --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

## Required ports

| Port | Purpose |
|---|---|
| `6432` | pgagroal listener (PostgreSQL wire protocol) |
| `9187` | Prometheus metrics (optional, disabled by default) |

## Minimal configuration

All configuration is via environment variables. Defaults are production-safe.

| Variable | Default | Purpose |
|---|---|---|
| `PG_BACKEND_HOST` | `postgres` | Upstream PostgreSQL host |
| `PG_BACKEND_PORT` | `5432` | Upstream PostgreSQL port |
| `PGAGROAL_PORT` | `6432` | pgagroal listen port |
| `PGAGROAL_HOST` | `*` | pgagroal bind address |
| `MAX_CONNECTIONS` | `100` | Max pooled connections |
| `PGAGROAL_LOG_LEVEL` | `info` | Log level |
| `PG_USERNAME` | — | Optional; registers a pgagroal user for frontend auth |
| `PG_PASSWORD` | — | Password for `PG_USERNAME` |

## Metrics

pgagroal ships a built-in Prometheus exporter. Enable it by exposing port `9187` and scraping `/metrics`. In the Helm chart this is `metrics.enabled=true`.

## Versioning and tags

Tags follow the project version in [VERSION](https://github.com/Elevarq/pgAgroal/blob/main/VERSION), not the upstream pgagroal version.

| Tag | Meaning |
|---|---|
| `1.3.0` | Exact release — pin this in production |
| `1.1` | Latest patch of the 1.1 line |
| `latest` | Most recent stable release — convenience only |

Only CI publishes tags. `latest` is a multi-arch manifest updated on every release.

## Helm chart

The Helm chart is published as an OCI artifact to GHCR alongside each release, so it installs by reference (the chart version matches the image tag):

```bash
helm install pgagroal oci://ghcr.io/elevarq/charts/pgagroal --version 1.3.0
```

The chart is cosign-signed with the same keyless GitHub OIDC identity as the image.

## Documentation

- Product documentation: [elevarq.com/docs/pgagroal-container](https://elevarq.com/docs/pgagroal-container)
- Source, full README, operations guide, Helm chart, and deployment examples: [github.com/Elevarq/pgAgroal](https://github.com/Elevarq/pgAgroal)

## Source and issues

- Source: [github.com/Elevarq/pgAgroal](https://github.com/Elevarq/pgAgroal)
- Bugs and feature requests: [GitHub Issues](https://github.com/Elevarq/pgAgroal/issues)
- Security: see [SECURITY.md](https://github.com/Elevarq/pgAgroal/blob/main/SECURITY.md)

Licensed under BSD-3-Clause. Contains unmodified pgagroal from [pgagroal/pgagroal](https://github.com/pgagroal/pgagroal).
