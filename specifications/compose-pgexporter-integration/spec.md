# Specification: pgagroal + pgexporter Integration Stack

Status: ACTIVE

> Issue: Elevarq/pgAgroal#42 (part of #1, upstream split).
> Confirmed 2026-05-29.

## Purpose

Evolve this repository's `docker-compose.yml` from a single-component
smoke-test harness (postgres + pgagroal + test-client) into a
**production-like integration example** that composes pgagroal
(connection pooling) and pgexporter (PostgreSQL metrics export) against
a PostgreSQL backend.

This realises the "integration layer" half of the upstream split agreed
in #1: focused, minimal single-component containers live upstream; this
repository composes them with hardened defaults and the inter-operation
wiring that makes them work together as a stack.

## Scope

Governs the Compose-based integration example in this repository:
`docker-compose.yml`, any pgexporter configuration assets it mounts,
and the documentation that describes running the stack.

Does NOT govern:
- The pgagroal container image's internal behaviour (covered by the
  existing image specs).
- The Helm chart (separate deployment path).
- The pgexporter image internals (lives upstream).

## Interfaces

### Services and their contracts

| Service | Role | Listens | Connects to |
|---|---|---|---|
| `postgres` | Backend database | 5432 (internal) | — |
| `pgagroal` | Connection pooler | 6432 (pooler, published), 2346 (native metrics, published) | `postgres:5432` |
| `pgexporter` | PostgreSQL metrics exporter | metrics port (published) | `postgres:5432` |

### Observability topology — two independent paths

The stack deliberately separates the data path from the observability
path, and uses one metrics source per layer:

- **Data path** (client/application traffic): client → `pgagroal:6432`
  → `postgres:5432`.
- **Server-metrics path**: `pgexporter` → `postgres:5432` directly,
  exposing PostgreSQL server metrics. NEVER routed through pgagroal
  (see R1, and rationale in issue #42).
- **Pooler-metrics path**: `pgagroal`'s own native metrics endpoint
  (`metrics = 2346`) exposes pooler metrics about pgagroal itself.

Each layer reports on itself; neither metrics path sits in the client
data path, and the two metrics paths are independent of one another.

### Inputs (pgexporter service)

| Input | Type | Constraints |
|---|---|---|
| backend host | string | Resolvable service name on the compose network (`postgres`) |
| backend port | int | Default 5432 |
| monitoring user | string | Must hold `pg_monitor` (or be superuser in the test stack) |
| monitoring password | string | Supplied via env / compose, never baked into an image |
| metrics port | int | The port pgexporter serves `/metrics` on |

### Outputs

| Output | Form |
|---|---|
| Pooled SQL connectivity | TCP on `pgagroal:6432`, forwarding to the backend |
| PostgreSQL metrics | HTTP `GET /metrics` on the pgexporter metrics port, Prometheus text format |

## Behaviors

| ID | Given | When | Then |
|---|---|---|---|
| B1 | A clean host, image(s) built | `docker compose up` is run | postgres, pgagroal, and pgexporter all reach a healthy/running state |
| B2 | The stack is up | A client connects to `pgagroal:6432` and runs a query | The query succeeds through the pool |
| B3 | The stack is up | `GET /metrics` is requested from pgexporter | HTTP 200 with Prometheus-format output containing at least one PostgreSQL-derived metric (pgexporter emits these as `pgexporter_pg_*` series) |
| B4 | The backend is slow to accept connections at startup | `docker compose up` is run | pgagroal and pgexporter wait for the backend to become healthy before reporting healthy themselves (ordered startup) |
| B5 | pgexporter is pointed at an unreachable backend | The stack is brought up | The failure is surfaced (pgexporter does not report healthy / metrics omit PostgreSQL series); the stack does not hang silently |
| B6 | The stack is up and healthy, then the backend stops | A client queries through pgagroal and `/metrics` is scraped | pgagroal connection attempts fail cleanly (no hang past `blocking_timeout`); pgexporter's HTTP endpoint still responds, with PostgreSQL series absent or marked unavailable |
| B7 | The stack is up | `GET /metrics` is requested from pgagroal's native metrics endpoint (port 2346) | HTTP 200 with Prometheus-format output containing pgagroal pooler metrics (e.g. a `pgagroal_*` series) |

## Rules

| ID | Rule |
|---|---|
| R1 | pgexporter MUST connect directly to `postgres`, NOT through pgagroal, so that pooler statistics are not polluted by the exporter's own scrape connections. |
| R2 | The monitoring credential MUST be supplied via environment/compose configuration, never baked into an image layer. |
| R3 | pgagroal and pgexporter MUST declare a `depends_on` health condition on `postgres` so startup is ordered. |
| R4 | The existing pooled-connection smoke test MUST be preserved as a validation step in the stack. |
| R5 | Service defaults MUST be consistent with the hardened posture already used by the Helm chart where applicable (non-root, health checks, no secrets in images). |
| R6 | Pooler metrics MUST be served by pgagroal's own native metrics endpoint, and server metrics by pgexporter. The two metrics sources MUST NOT be merged into a single path, and neither MUST sit in the client data path. |

## Invariants

| ID | Invariant |
|---|---|
| I1 | The stack is reproducible from committed sources alone — `docker compose up` requires no manual post-steps. |
| I2 | No secret is committed to the repository or baked into an image; credentials enter only at runtime via compose/env. |
| I3 | pgagroal remains the sole pooling path for client traffic; pgexporter never sits in the client data path. |
| I4 | Removing pgexporter from the stack leaves the pgagroal pooling behaviour unchanged (the exporter is additive, not load-bearing for pooling). |
| I5 | The two observability paths are independent: pgexporter being unavailable does not affect pgagroal's native metrics endpoint, and vice versa. |

## Failure conditions

| Trigger | System response |
|---|---|
| Backend never becomes healthy | Dependent services do not report healthy; `docker compose up` does not falsely indicate a working stack (B5). |
| Monitoring user lacks `pg_monitor` | pgexporter starts but PostgreSQL metric series are missing/empty; surfaced via B3 assertion failing, not a silent pass. |
| Backend lost after startup | pgagroal returns connection errors within `blocking_timeout`; pgexporter endpoint stays up with PostgreSQL series unavailable (B6). |

## Constraints

- Use upstream pgexporter as the metrics component, built from a pinned
  upstream ref (no published image exists). Do not fork pgexporter or
  vendor its source into this repository — the build clones the pinned
  upstream tag, mirroring how this repo builds pgagroal. A thin
  env-templating entrypoint (config generation only) is permitted; it
  does not modify pgexporter itself.
- No new exposed port beyond the pooler port and the pgexporter metrics
  port.
- Backend image and pgagroal image selections remain pinned (no
  `:latest`).
- Changes confined to compose, pgexporter config assets, tests, and docs.

## Non-goals

- Adding pgopr to the stack (tracked separately in #44).
- Shipping a production Prometheus/Grafana stack — this is an
  integration *example*, not a full observability deployment. (The two
  metrics endpoints are exposed; scraping/storage/dashboards are out of
  scope.)
- Replacing the Helm chart's metrics path.

## Traceability

| Spec element | Acceptance case |
|---|---|
| B1, R3, I1 | AC-01 |
| B2, B3, R1, R4, I3 | AC-02 |
| B4, R3 | AC-03 |
| B5, failure (unreachable backend) | AC-04 |
| B6, I4 | AC-05 |
| B7, R6, I5 | AC-06 |
