# Acceptance Cases: pgagroal + pgexporter Integration Stack

Derived from `spec.md`. Each case maps to behaviors, rules, or
invariants in the specification. Minimum set: one normal, one boundary,
one invalid, one failure.

## AC-01: Stack comes up cleanly (normal)

**Spec refs**: B1, R3, I1

**Given**: a clean host, images built from committed sources
**When**: `docker compose up -d`
**Then**:
- `postgres`, `pgagroal`, and `pgexporter` all reach healthy/running
  within the configured healthcheck windows
- No manual post-step is required
- Startup is ordered: pgagroal and pgexporter only report healthy after
  `postgres` is healthy

## AC-02: Pooled query and metrics both work (normal)

**Spec refs**: B2, B3, R1, R4, I3

**Given**: the stack from AC-01 is up and healthy
**When**:
- a client runs `SELECT 1` via `pgagroal:6432`, AND
- `GET /metrics` is requested from the pgexporter metrics port
**Then**:
- The pooled query returns successfully (preserves the existing smoke
  test)
- The metrics request returns HTTP 200, Prometheus text format,
  containing at least one PostgreSQL-derived series (pgexporter emits
  these as `pgexporter_pg_*` metrics)
- pgexporter's connection to the backend is direct (verified by config:
  its target host is `postgres`, not `pgagroal`)

## AC-03: Ordered startup under slow backend (boundary)

**Spec refs**: B4, R3

**Given**: the backend is artificially slow to accept connections
(e.g. healthcheck not yet passing)
**When**: `docker compose up` is run
**Then**:
- pgagroal and pgexporter do NOT report healthy before `postgres` is
  healthy
- Once `postgres` becomes healthy, both dependents converge to healthy
- The harness exits 0 after convergence

## AC-04: Unreachable backend is surfaced, not hidden (invalid)

**Spec refs**: B5, failure condition (unreachable backend)

**Given**: pgexporter is configured with a backend host that does not
resolve / is not listening
**When**: the stack is brought up
**Then**:
- pgexporter does NOT report healthy, OR `/metrics` omits PostgreSQL
  series (no `pgexporter_pg_*` metrics present)
- `docker compose up` does not falsely indicate a fully working stack
- The condition is observable from compose/healthcheck status — no
  silent pass

## AC-05: Backend loss after startup degrades cleanly (failure)

**Spec refs**: B6, I4

**Given**: the stack is up and healthy
**When**: `postgres` is stopped, then a client queries via pgagroal and
`/metrics` is scraped
**Then**:
- pgagroal connection attempts fail within `blocking_timeout` (no
  indefinite hang)
- pgexporter's HTTP endpoint still responds (exporter process stays up)
- PostgreSQL metric series are absent or marked unavailable
- Removing pgexporter entirely from the compose file leaves the
  pgagroal pooling path behaviour unchanged (I4, verified by inspection
  / a pgagroal-only run)

## AC-06: pgagroal native metrics endpoint (dual-path observability)

**Spec refs**: B7, R6, I5

**Given**: the stack from AC-01 is up and healthy
**When**: `GET /metrics` is requested from pgagroal's native metrics
endpoint on port 2346
**Then**:
- The request returns HTTP 200, Prometheus text format, containing at
  least one pgagroal pooler series (e.g. a `pgagroal_*` metric)
- This path is independent of pgexporter: stopping pgexporter does not
  affect the pgagroal metrics endpoint (I5)
- The pgagroal metrics endpoint is a distinct port from the pooler port
  (2346 vs 6432), confirming the metrics path does not sit in the client
  data path
