# Elevarq pgAgroal

A high-performance **PostgreSQL connection pooler**. pgAgroal fronts an existing
PostgreSQL database that *you* supply: other workloads in the GVC connect to
pgAgroal on TCP **6432**, and pgAgroal multiplexes those clients onto a small pool
of backend connections — cutting connection overhead and latency. It is
**stateless** (no volume required) and packages the upstream
[pgagroal](https://github.com/pgagroal/pgagroal) pooler.

## What this template deploys

| Resource | Purpose |
|----------|---------|
| `workload` (standard, stateless) | The pgAgroal pooler; `replicas` independent instances |
| `secret` (dictionary) | The backend PostgreSQL password |
| `identity` + `policy` | Least-privilege `reveal` access to the secret |

The image is pinned by immutable digest
(`ghcr.io/elevarq/pgagroal@sha256:36017745…`, the `1.4.5` multi-arch index —
`linux/amd64` + `linux/arm64`, cosign-signed).

## Prerequisites

- An existing, reachable PostgreSQL instance (pgAgroal bundles no database).
- A PostgreSQL role clients will pool through (`auth.username`/`auth.password`) —
  a role with `CONNECT` on the target database(s) plus the application-required
  schema and object privileges. pgAgroal only pools; it
  performs no admin/maintenance on the backend.

## How clients connect

Point your other GVC workloads at the pooler instead of PostgreSQL directly:

```
host=<release>-pgagroal.<gvc>.cpln.local  port=6432  user=<auth.username>  password=<auth.password>
```

Only the pre-registered `auth.username` is accepted (unknown users are rejected).

## Required inputs

| Value | Description |
|-------|-------------|
| `backend.host` | PostgreSQL host/IP reachable from the GVC |
| `auth.username` | A valid backend PostgreSQL user clients pool through |
| `auth.password` | Password for that user (stored in a Control Plane secret) |

## Common optional inputs

| Value | Default | Description |
|-------|---------|-------------|
| `backend.port` | `5432` | Backend PostgreSQL port |
| `pool.maxConnections` | `100` | Maximum pooled connections |
| `replicas` | `1` | Independent pooler instances (stateless) |
| `logLevel` | `info` | `fatal`\|`error`\|`warn`\|`info`\|`debug1`..`debug5`\|`trace` |
| `metrics.enabled` | `false` | Expose pgAgroal Prometheus `/metrics` on `:2346` (unauthenticated) |
| `tls.enabled` | `false` | Frontend TLS (client → pooler) — see Frontend TLS |
| `tls.cert` / `tls.key` | `""` | PEM server certificate / private key (required when `tls.enabled`) |
| `tls.mutualTLS` | `false` | Also require and verify client certificates (verify-ca) |
| `tls.caCert` | `""` | PEM client CA bundle (required when `tls.mutualTLS`) |
| `hbaSource` | `all` | Client source allow-list (CIDRs or `all`) — see Notes |
| `resources.cpu` / `resources.memory` | `100m` / `128Mi` | Scale memory with `maxConnections` |
| `firewall.external.outboundAllowCIDR` | `[0.0.0.0/0]` | Egress to the backend (egress is also port-scoped to `backend.port`); narrow to the DB CIDR if stable |

## Verifying it works

- **Pooler up:** the workload readiness/liveness probe runs `pgagroal-cli … ping`
  (the pooler is ready when this passes). Check the workload status in the console.
- **Metrics** (when `metrics.enabled=true`): `GET http://<release>-pgagroal.<gvc>.cpln.local:2346/metrics`.
- **End to end:** connect a client to `:6432` with `auth.username`/`auth.password`
  and run a query — it is proxied to the backend.

## Frontend TLS

Client → pooler TLS is off by default. To enable it, supply a PEM server
certificate and private key:

```
tls.enabled = true
tls.cert    = <PEM server certificate>
tls.key     = <PEM server private key>
```

The certificate and key are stored in Control Plane **opaque secrets**, revealed
only to the pgAgroal identity and mounted read-only; the entrypoint installs the
key at `0600` as pgAgroal requires. Clients then connect to `:6432` with
`sslmode=require` (or `verify-ca`/`verify-full` against your own CA).

For **mutual TLS** (require and verify client certificates), also set:

```
tls.mutualTLS = true
tls.caCert    = <PEM CA bundle that signed the client certificates>
```

Client-certificate checking is `verify-ca` (the certificate must chain to
`tls.caCert`); the pgAgroal 2.1.0 pooler has no `tls_cert_auth_mode` key, so
`verify-full`-style CN/SAN matching at the pooler is not available. Backend TLS
(pooler → PostgreSQL) is negotiated by pgAgroal from the backend host and is not
configured by this template.

## Notes & limitations

- **`hbaSource` defaults to `all`.** Network access to `:6432` is already restricted
  to the same GVC by the workload firewall (`firewall.internal.inboundAllowType`),
  which is the network gate. pgAgroal's HBA CIDR matching is octet-boundary-only and
  cannot express many cloud pod networks (e.g. `100.64.0.0/10`), so an explicit CIDR
  can wrongly reject in-GVC clients. Set CIDRs only if your client addressing is
  stable and you want an extra app-layer allow-list.
- Backend connectivity is not checked at startup — the pooler starts and serves; a
  bad backend surfaces on the first client connection.

## Security model

- Runs as non-root (UID/GID 1000) under Control Plane's restricted container
  capabilities. Stateless — no persisted data.
- The backend password is held in a Control Plane secret, revealed only to the
  pgAgroal identity via the bundled policy — never baked into the image.
- Only the pre-registered user is accepted (`PGAGROAL_ALLOW_UNKNOWN_USERS` off);
  egress is restricted to the backend's TCP port.

Source & docs: https://github.com/Elevarq/pgAgroal
