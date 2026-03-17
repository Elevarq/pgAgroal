# pgagroal Container

[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](LICENSE)

Production-grade Docker container and Helm chart for [pgagroal](https://github.com/pgagroal/pgagroal) 2.0.2 -- a high-performance PostgreSQL connection pooler.

## Architecture

```
                ┌──────────────┐
 Client ──────▶│  pgagroal     │──────▶ PostgreSQL / RDS
   :6432       │  (pooler)     │         :5432
                └──────────────┘
```

pgagroal sits between clients and PostgreSQL, maintaining a pool of persistent backend connections. This project provides:

- **Multi-stage Dockerfile** -- reproducible build from source
- **Helm chart** -- production Kubernetes/EKS packaging with PDB, security contexts, and Prometheus metrics
- **CI pipeline** -- hadolint, ShellCheck, Helm lint, integration + resilience + failure-mode tests
- **Test suite** -- pooling validation, backend restart, concurrent load, startup failure, credential errors
- **Non-root runtime** (UID 1000), all capabilities dropped, seccomp enforced

## Quick Start (Docker)

```bash
make run
psql -h localhost -p 6432 -U testuser -d testdb -c 'SELECT 1;'
make stop
```

## Quick Start (Helm)

```bash
make build                       # build image
make helm-lint                   # validate chart
helm install pgagroal helm/pgagroal/ \
  --set postgresql.host=my-pg \
  --set credentials.username=app \
  --set credentials.password=secret
```

## Project Structure

```
pgagroal-container/
├── Dockerfile
├── entrypoint.sh
├── pgagroal.conf.template
├── pgagroal_hba.conf.template
├── docker-compose.yml
├── Makefile
├── VERSION
├── LICENSE
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── test/
│   ├── container-start-test.sh
│   ├── backend-restart-test.sh
│   ├── concurrent-connection-test.sh
│   ├── pooling-behavior-test.sh
│   ├── startup-failure-test.sh
│   ├── invalid-credentials-test.sh
│   └── secret-rotation-procedure.md
├── helm/
│   └── pgagroal/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-eks-example.yaml
│       ├── values-client-example.yaml
│       ├── values-client-minimal.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── configmap.yaml
│           ├── secret.yaml
│           ├── serviceaccount.yaml
│           ├── pdb.yaml
│           └── NOTES.txt
├── docs/
│   ├── eks-deployment.md
│   ├── operations.md
│   ├── failure-modes.md
│   ├── release-checklist.md
│   └── first-client-deployment.md
├── .github/
│   └── workflows/
│       └── container-ci.yml
└── README.md
```

## Configuration

All settings are configurable via environment variables (Docker) or Helm values (Kubernetes):

| Variable / Helm value | Default | Description |
|---|---|---|
| `PGAGROAL_HOST` / `pgagroal.host` | `*` | Bind address |
| `PGAGROAL_PORT` / `pgagroal.port` | `6432` | Bind port |
| `PG_BACKEND_HOST` / `postgresql.host` | `postgres` | PostgreSQL host |
| `PG_BACKEND_PORT` / `postgresql.port` | `5432` | PostgreSQL port |
| `PG_USERNAME` / `credentials.username` | *(unset)* | Pooler user (optional) |
| `PG_PASSWORD` / `credentials.password` | *(unset)* | Pooler password (optional) |
| `MAX_CONNECTIONS` / `pgagroal.maxConnections` | `100` | Maximum pool connections |
| `PGAGROAL_LOG_LEVEL` / `pgagroal.logLevel` | `info` | Log level |

### Custom Configuration (Docker)

Mount your own config files to override the templates:

```bash
docker run -d \
  -v /path/to/pgagroal.conf:/etc/pgagroal/pgagroal.conf \
  -v /path/to/pgagroal_hba.conf:/etc/pgagroal/pgagroal_hba.conf \
  -p 6432:6432 \
  pgagroal:2.0.2
```

## Docker Compose

The included `docker-compose.yml` starts a full stack:

- **postgres** -- PostgreSQL 17.4 backend
- **pgagroal** -- connection pooler
- **test-client** -- one-shot client that verifies connectivity

```bash
docker compose up -d postgres pgagroal
docker compose run --rm test-client
```

## Helm Chart

### Install

```bash
helm install pgagroal helm/pgagroal/ \
  --set postgresql.host=my-postgres-service \
  --set credentials.username=app_user \
  --set credentials.password=secret \
  -n pgagroal --create-namespace
```

### Use an Existing Secret

Create the secret yourself (or via External Secrets Operator) and reference it:

```bash
kubectl create secret generic my-pg-creds \
  --from-literal=PG_USERNAME=app_user \
  --from-literal=PG_PASSWORD=secret

helm install pgagroal helm/pgagroal/ \
  --set postgresql.host=my-postgres-service \
  --set credentials.create=false \
  --set credentials.existingSecret=my-pg-creds
```

### First Client Deployment (EKS)

Full walkthrough: [docs/first-client-deployment.md](docs/first-client-deployment.md)

```bash
# 1. Create namespace and secret
kubectl create namespace pgagroal
kubectl -n pgagroal create secret generic pgagroal-pg-credentials \
  --from-literal=PG_USERNAME=app_user \
  --from-literal=PG_PASSWORD='<password>'

# 2. Copy and edit the values file
cp helm/pgagroal/values-client-minimal.yaml client-values.yaml
# Edit: image.repository, postgresql.host

# 3. Install
helm install pgagroal helm/pgagroal/ -f client-values.yaml -n pgagroal

# 4. Smoke test
kubectl -n pgagroal run smoke --rm -it --restart=Never \
  --image=postgres:17.4-bookworm --env="PGPASSWORD=<password>" \
  -- psql -h pgagroal -p 6432 -U app_user -d mydb -c "SELECT 1;"
```

The guide includes an operational acceptance checklist to complete before client handoff.

### EKS Reference

Detailed infrastructure guide: [docs/eks-deployment.md](docs/eks-deployment.md) (ECR setup, IRSA, Security Groups, monitoring).

## Testing

### Test Matrix

| Test | Command | CI | What it validates |
|---|---|---|---|
| Integration | `make test` | Yes | Build, start, health check, psql connectivity |
| Backend restart | `make test-backend-restart` | Yes | pgagroal recovers after PostgreSQL restart |
| Concurrent load | `make test-concurrent` | No | Pool handles 20 parallel connections |
| Pooling behavior | `make test-pooling` | No | Backend connection reuse via `pg_backend_pid()` |
| Startup failure | `make test-startup-failure` | Yes | Daemon survives unreachable backend |
| Invalid credentials | `make test-invalid-creds` | No | Clean auth error, no daemon crash |
| Validation suite | `make test-validation` | -- | Runs pooling + startup + creds |
| All tests | `make test-all` | -- | Runs every test sequentially |
| Helm lint | `make helm-lint` | Yes | Chart structure and values |
| Helm render | `make helm-template` | Yes | Template rendering without cluster |

### Running Tests

```bash
# Basic integration test
make test

# Backend restart resilience
make test-backend-restart

# Concurrent connections (default 20, override with CONCURRENCY=50)
make test-concurrent

# Pool behavior validation (checks pg_backend_pid reuse)
make test-pooling

# Startup with no backend (failure-mode)
make test-startup-failure

# Wrong password handling
make test-invalid-creds

# All phase-4 validation tests
make test-validation

# Everything
make test-all
```

## Makefile Targets

| Target | Description |
|---|---|
| `make build` | Build the container image |
| `make run` | Build and start postgres + pgagroal |
| `make test` | Run Docker integration test |
| `make test-backend-restart` | Run backend restart resilience test |
| `make test-concurrent` | Run concurrent connection test |
| `make test-pooling` | Validate connection pooling behavior |
| `make test-startup-failure` | Test startup with unavailable backend |
| `make test-invalid-creds` | Test invalid credential handling |
| `make test-validation` | Run all phase-4 validation tests |
| `make test-all` | Run every test sequentially |
| `make stop` | Stop all services |
| `make clean` | Remove containers, volumes, and image |
| `make logs` | Tail pgagroal logs |
| `make helm-lint` | Lint the Helm chart |
| `make helm-template` | Render Helm templates (dry-run) |
| `make helm-install` | Install chart into current cluster |
| `make helm-upgrade` | Upgrade existing Helm release |
| `make helm-uninstall` | Remove Helm release |

## CI Pipeline

The GitHub Actions workflow (`.github/workflows/container-ci.yml`) runs on every push and PR:

1. **Lint** -- hadolint on the Dockerfile, ShellCheck on entrypoint.sh
2. **Helm lint** -- `helm lint` + `helm template` dry-run
3. **Build** -- Docker Buildx build with GHA cache
4. **Integration test** -- full docker-compose stack with psql connectivity check
5. **Resilience test** -- backend restart recovery validation
6. **Startup failure test** -- daemon behavior with unreachable backend

The concurrent, pooling, and invalid-credentials tests are excluded from CI to avoid flakiness in resource-constrained runners. Run them locally with `make test-all`.

## Operations

Full operational guide: [docs/operations.md](docs/operations.md).

Key topics:
- Startup sequence (Docker and Kubernetes)
- Readiness/liveness probe behavior and tuning
- Backend restart recovery semantics
- Scaling guidance (replicas vs. backend `max_connections`)
- Credential rotation: [test/secret-rotation-procedure.md](test/secret-rotation-procedure.md)
- Troubleshooting checklist

### Failure Modes

Comprehensive failure mode documentation: [docs/failure-modes.md](docs/failure-modes.md).

Every failure mode has been tested and documented with:
- Trigger condition
- Observed behavior (does pgagroal crash? does health check pass?)
- Operator-facing symptoms
- Recovery path (automatic vs. manual)

Summary:

| Failure | Crashes? | Health check? | Auto-recovery? |
|---|---|---|---|
| Backend down on startup | No | Passes | Yes |
| Backend restart | No | Passes | Yes |
| Invalid credentials | No | Passes | N/A (client error) |
| DNS failure | No | Passes | Yes |
| Pool exhaustion | No | Passes | Yes (when clients release) |

### Known Limitations

- pgagroal does not drain active connections on `SIGTERM`; in-flight queries may be interrupted
- Maximum 64 backend server sections, 10,000 pooled connections
- Config reload via `SIGHUP` is partial; rolling restart is safer
- `pgagroal-cli ping` checks daemon liveness, not backend reachability
- Pooling reuse rate depends on `pipeline` mode; `session` (default) reuses on disconnect, `transaction` reuses after each statement

### Release Process

See [docs/release-checklist.md](docs/release-checklist.md) for the full release procedure, including:
- Version string locations (`VERSION`, `Dockerfile`, `Chart.yaml`, `Makefile`)
- Image tagging conventions (no `latest` tag)
- ECR and GHCR publish steps
- Helm chart versioning

## Security

The container and Helm chart enforce production security defaults:

| Control | Setting |
|---|---|
| Non-root | `runAsUser: 1000`, `runAsNonRoot: true` |
| No privilege escalation | `allowPrivilegeEscalation: false` |
| Capabilities | All dropped |
| Seccomp | `RuntimeDefault` |
| Read-only root filesystem | `readOnlyRootFilesystem: true` (K8s); `/etc/pgagroal` and `/tmp` use emptyDir |
| Service account | `automountServiceAccountToken: false` |
| Secrets | Injected via K8s Secrets, never baked into the image |

## Monitoring and Observability

### pgagroal Built-in Metrics

pgagroal exposes Prometheus metrics when configured. In the Helm chart:

```yaml
metrics:
  enabled: true
  port: 9187
```

This adds `metrics = 9187` to the pgagroal config and exposes the port on the Service. Pair with a ServiceMonitor for the Prometheus Operator:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: pgagroal
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: pgagroal
  endpoints:
    - port: metrics
      interval: 15s
```

### CLI-based Monitoring

`pgagroal-cli` provides runtime pool introspection:

```bash
# Inside the container or via kubectl exec:
pgagroal-cli -c /etc/pgagroal/pgagroal.conf status          # pool summary
pgagroal-cli -c /etc/pgagroal/pgagroal.conf status details   # per-connection detail
```

### Observability Sidecar (Elevarq Integration Roadmap)

The Helm chart includes a stub for attaching a future observability sidecar (e.g. an Elevarq collector or custom exporter). This is disabled by default and no fake exporter is included.

To prepare for integration, set values like:

```yaml
observability:
  sidecar:
    enabled: true
    image: "your-registry/elevarq-pgagroal-exporter"
    tag: "0.1.0"
    port: 9188
    resources:
      requests:
        cpu: 50m
        memory: 32Mi
      limits:
        cpu: 200m
        memory: 64Mi
    env:
      - name: PGAGROAL_SOCKET_DIR
        value: /tmp
    extraVolumeMounts: []
```

The sidecar container:
- Shares the `/tmp` emptyDir with pgagroal (read-only access to the management unix socket)
- Gets its own port exposed on the Service (`obs-metrics`)
- Inherits the same security context (non-root, no capabilities, seccomp)
- Can read `pgagroal-cli status` output or connect to the management socket directly

**Integration path for an Elevarq collector:**
1. Build an exporter that calls `pgagroal-cli status details` (or reads the management socket) and exposes metrics on `/metrics`
2. Set `observability.sidecar.enabled: true` with the exporter image
3. Point Prometheus at the `obs-metrics` port
4. Build Grafana dashboards from the exported metrics

## Pinned Versions

| Component | Version | Notes |
|---|---|---|
| Project release | 0.1.0 | `VERSION` file, git tag `v0.1.0` |
| pgagroal | 2.0.2 | Upstream, built from source |
| Debian base | bookworm-20250224-slim | Pinned snapshot |
| PostgreSQL (compose) | 17.4-bookworm | Test backend |
| Helm chart | 0.1.0 | `Chart.yaml` version |

## License

[BSD-3-Clause](LICENSE)
