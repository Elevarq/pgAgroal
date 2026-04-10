# pgAgroal

Production-grade Docker container for [pgagroal](https://github.com/pgagroal/pgagroal) -- a high-performance PostgreSQL connection pooler.

## Quick Start

```bash
docker run -d --name pgagroal \
  -p 6432:6432 \
  -e PG_BACKEND_HOST=192.168.1.100 \
  -e PG_BACKEND_PORT=5432 \
  elevarq/pgagroal:1.0.0
```

Change `192.168.1.100` to the address of your PostgreSQL server.

Connect through pgagroal:

```bash
psql -h localhost -p 6432 -U postgres -d postgres
```

## Configuration

Configuration is via environment variables. No config files need to be mounted.

| Variable | Default | Description |
|---|---|---|
| `PG_BACKEND_HOST` | `postgres` | PostgreSQL host |
| `PG_BACKEND_PORT` | `5432` | PostgreSQL port |
| `PGAGROAL_HOST` | `*` | Bind address |
| `PGAGROAL_PORT` | `6432` | Bind port |
| `MAX_CONNECTIONS` | `100` | Maximum pool connections |
| `PGAGROAL_LOG_LEVEL` | `info` | Log level |

## Images

| Tag | Description |
|---|---|
| `1.0.0` | Current stable release |
| `1.0` | Latest patch in the 1.0 line |
| `latest` | Most recent stable release |

Multi-arch: `linux/amd64`, `linux/arm64`.

## Supply Chain Security

Images are built by GitHub Actions and signed with [Cosign](https://docs.sigstore.dev/cosign/overview/) using keyless GitHub OIDC. SBOM and SLSA provenance attestations are attached.

Verify before deployment:

```bash
cosign verify elevarq/pgagroal:1.0.0 \
  --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

### Kubernetes / Helm

Pin a version tag in Helm values:

```yaml
image:
  repository: elevarq/pgagroal
  tag: "1.0.0"
  pullPolicy: IfNotPresent
```

Verify before rollout:

```bash
cosign verify elevarq/pgagroal:1.0.0 \
  --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

Clusters that enforce image trust can require valid Cosign signatures at admission time using [Sigstore Policy Controller](https://docs.sigstore.dev/policy-controller/overview/) or [Kyverno](https://kyverno.io/).

## Source

[github.com/Elevarq/pgAgroal](https://github.com/Elevarq/pgAgroal)

## License

[BSD-3-Clause](https://github.com/Elevarq/pgAgroal/blob/main/LICENSE)
