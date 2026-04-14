# Specification: Container Survives `docker restart`

Status: ACTIVE

## Purpose

Ensure the `pgagroal` container image tolerates a full stop/start cycle
(`docker restart`, Kubernetes pod restart on the same node with an
ephemeral writable layer retained, systemd service restart, etc.)
without operator intervention.

The immediate trigger is a defect observed in upstream `pgagroal`:
the PID file (`/tmp/pgagroal.<port>.pid`) is only removed during the
graceful SIGTERM shutdown path. When the process is terminated by
SIGKILL — including the Docker stop→kill escalation after grace
expiry, OOM kills, host crashes, and `docker kill` — no cleanup runs
and the PID file is left behind. Because the container image keeps
the PID file on the writable filesystem layer, the stale file
survives a subsequent `docker start` and pgagroal refuses to start:

```
pgagroal: PID file </tmp//pgagroal.6433.pid> exists, is there another instance running ?
```

The container then exits with status 1 and the healthcheck fails.

This specification pins down the invariant the container is expected
to guarantee, independent of upstream behavior.

## Scope

Applies to the `pgagroal` container image produced by this repository
(`Dockerfile`, `entrypoint.sh`, configuration templates).

Does NOT govern upstream `pgagroal` source behavior. Upstream fixes
are tracked separately; the container guarantee must hold whether or
not upstream ships a fix.

## Interfaces

No new inputs, outputs, or CLI arguments are introduced. The guarantee
is a behavioral invariant of the image.

Relevant existing inputs:

| Input | Effect on PID file location |
|---|---|
| `PGAGROAL_PORT` env var (default `6432`) | PID file path is `/tmp/pgagroal.${PGAGROAL_PORT}.pid` |

## Behaviors

| ID | Given | When | Then |
|---|---|---|---|
| B1 | Container started from a fresh filesystem | Container is started | pgagroal starts, becomes healthy |
| B2 | Container was terminated ungracefully (SIGKILL, OOM, host crash, stop-grace expiry) leaving `/tmp/pgagroal.<port>.pid` on the writable layer | Container is started again (`docker start` or `docker restart`) | pgagroal starts, becomes healthy |
| B3 | Container is running | SIGTERM delivered to PID 1 | Container exits with status 0 within the platform's stop grace period (upstream already handles this; covered as a baseline invariant) |
| B4 | Container previously shut down cleanly via SIGTERM (PID file already removed by upstream) | Container is started again | pgagroal starts, becomes healthy (entrypoint guard is a no-op) |

## Rules

| ID | Rule |
|---|---|
| R1 | Before `exec pgagroal`, the entrypoint MUST remove any pre-existing PID file at `/tmp/pgagroal.${PGAGROAL_PORT}.pid`. |
| R2 | The removal MUST be idempotent — absence of the file is not an error. |
| R3 | The entrypoint MUST NOT remove any other file under `/tmp/` (the Unix socket directory is also `/tmp/`). |

## Invariants

| ID | Invariant |
|---|---|
| I1 | A stale PID file never blocks container startup. |
| I2 | The fix is self-contained in the image. Consumers do not need to mount a tmpfs, add a volume, or change their `docker run` / compose / Helm invocations. |
| I3 | The entrypoint's behavior on first start (no stale PID file) is unchanged. |

## Failure conditions

| Trigger | System response |
|---|---|
| PID file path is not writable (should not happen — `/tmp/` is always writable) | `rm -f` fails silently; pgagroal start may then fail. Treated as an environment bug, not a spec violation. |
| Another process is listening on `PGAGROAL_PORT` inside the container namespace | pgagroal exits with its normal bind error. Out of scope for this spec. |

## Constraints

- No dependency added beyond `rm` (coreutils) already present in the base image.
- No change to image size, base image, or exposed ports.
- No change to configuration template defaults.

## Non-goals

- Fixing upstream pgagroal's SIGTERM handler. That is pursued separately and, once merged and pinned here, the container-side guard becomes redundant but is retained as defense-in-depth.
- Guaranteeing behavior across filesystem corruption, OOM kills mid-write, or `SIGKILL` followed by writable-layer loss — those are orthogonal failure modes.
- Preventing startup when a *live* pgagroal process still holds the port (this is a misconfiguration, not a restart scenario).

## Traceability

| Spec element | Acceptance case |
|---|---|
| B1, I3 | AC-01 |
| B2, R1, R2, I1 | AC-02 |
| B3, B4 | AC-03 |
| R3 | AC-04 |
