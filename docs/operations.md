# Operations Guide

Operational reference for running pgagroal in production.

## Startup Sequence

### Docker Compose

1. PostgreSQL starts and runs its health check (`pg_isready`)
2. pgagroal starts after PostgreSQL is healthy (`depends_on: condition: service_healthy`)
3. `entrypoint.sh` generates config from templates via `envsubst`
4. If `PG_USERNAME`/`PG_PASSWORD` are set, registers the user with `pgagroal-admin`
5. `pgagroal` starts in foreground mode (`-d` flag)
6. Docker HEALTHCHECK polls `pgagroal-cli ping` every 10s

### Kubernetes

1. Init container copies ConfigMap templates into writable emptyDir at `/etc/pgagroal`
2. Main container runs the same `entrypoint.sh` startup
3. Readiness probe (`pgagroal-cli ping`, every 5s) gates traffic to the pod
4. Liveness probe (`pgagroal-cli ping`, every 10s) restarts the pod if pgagroal hangs

**Important**: pgagroal does not wait for the backend to be reachable before starting. It accepts client connections immediately. If the backend is down, clients receive a connection error from pgagroal (not a timeout). This is the correct behavior for a pooler -- it starts fast and lets clients retry.

## Readiness and Liveness Behavior

### pgagroal-cli ping

`pgagroal-cli -c /etc/pgagroal/pgagroal.conf ping` checks whether the pgagroal daemon process is responsive. It connects to the management socket and returns exit code 0 (alive) or 1 (unreachable).

**What it tests**: the pgagroal process is running and its management interface accepts connections.

**What it does NOT test**: whether the PostgreSQL backend is reachable or whether the connection pool has available slots.

This is intentional. A pooler should remain ready even when the backend is temporarily unavailable, so that it can:
- Return informative errors to clients
- Resume service immediately when the backend recovers
- Avoid cascading pod restarts during a brief backend blip

### Probe Tuning

| Setting | Default | Notes |
|---|---|---|
| Readiness `periodSeconds` | 5 | Lower = faster detection, more exec overhead |
| Readiness `failureThreshold` | 2 | 2 failures x 5s = 10s before pod is removed from Service |
| Liveness `periodSeconds` | 10 | Higher than readiness to avoid premature restarts |
| Liveness `failureThreshold` | 3 | 3 failures x 10s = 30s before pod is killed |

For high-traffic deployments, consider increasing `failureThreshold` on liveness to avoid killing pods during transient load spikes.

## Backend Restart Behavior

pgagroal handles backend restarts gracefully:

1. When PostgreSQL stops, existing pooled connections become invalid
2. pgagroal detects broken connections when clients attempt to use them
3. New client connections trigger fresh backend connections
4. Once PostgreSQL is back, pgagroal resumes normal operation

**Tested behavior** (see `test/backend-restart-test.sh`):
- pgagroal stays running during backend outage (does not crash)
- pgagroal-cli ping continues to report healthy (daemon is alive)
- New client connections succeed within seconds of backend recovery
- No manual intervention required

**Configuration that affects recovery**:

| Setting | Effect |
|---|---|
| `validation = foreground` | Validates each connection before handing it to a client. Adds latency but catches stale connections earlier. |
| `validation = background` | Periodic sweep removes broken connections. Less latency but stale connections may be served briefly. |
| `idle_timeout` | Idle connections are closed after this period. Helps clean up stale connections after a backend restart. |
| `blocking_timeout` | Maximum time a client waits for a connection. Default 30s. |

## Known Limitations

1. **No built-in TLS termination to clients by default**. TLS must be configured explicitly via `tls`, `tls_cert_file`, `tls_key_file` in pgagroal.conf. In Kubernetes, TLS is typically handled by a sidecar proxy or service mesh.

2. **Maximum 64 server backends**. pgagroal supports up to 64 `[server]` sections. For read replicas, this is usually sufficient.

3. **Maximum 10,000 connections**. The `max_connections` setting caps at 10,000. Ensure this aligns with PostgreSQL's own `max_connections`.

4. **Unix socket directory must be writable**. pgagroal writes management sockets to `unix_socket_dir` (`/tmp` in our config). In Kubernetes, `/tmp` is an emptyDir volume.

5. **Config reload requires restart**. pgagroal supports `SIGHUP` for some settings, but not all. For guaranteed consistency, perform a rolling restart after config changes (the Helm chart's `checksum/config` annotation handles this).

6. **No native connection draining on shutdown**. When pgagroal receives `SIGTERM`, it shuts down. Active queries may be interrupted. Set `terminationGracePeriodSeconds` high enough for in-flight queries to complete and use a `preStop` hook if needed.

## Scaling Guidance

### Horizontal Scaling (replicas)

pgagroal instances are stateless -- each maintains its own independent connection pool to the backend. Scaling replicas is safe with these considerations:

| Replicas | Backend connections | Notes |
|---|---|---|
| 1 | Up to `max_connections` | No HA. Acceptable for dev/staging. |
| 2 | Up to `2 * max_connections` | Minimum for production with PDB. |
| 3 | Up to `3 * max_connections` | Recommended for EKS (1 per AZ). |

**Watch out**: total backend connections = `replicas * max_connections`. Ensure PostgreSQL's `max_connections` can accommodate this. For RDS, also account for connections from other services and the RDS reserved connections (typically 3).

Formula:
```
pgagroal max_connections <= (PG max_connections - reserved - other_services) / replicas
```

### Vertical Scaling

pgagroal is lightweight. Typical resource usage:
- CPU: sub-100m idle, spikes during connection storms
- Memory: ~2-4 MB per pooled connection

Start with `cpu: 100m / memory: 64Mi` requests and adjust based on observed usage.

## Credential Rotation

See [test/secret-rotation-procedure.md](../test/secret-rotation-procedure.md) for step-by-step instructions.

## Troubleshooting Checklist

### Container won't start

- [ ] Check `docker compose logs pgagroal` or `kubectl logs <pod> -c pgagroal`
- [ ] Verify config template syntax: run `make run` and check for envsubst errors
- [ ] Ensure `/etc/pgagroal` is writable (K8s: emptyDir mounted?)

### Connections refused

- [ ] Is pgagroal healthy? `pgagroal-cli -c /etc/pgagroal/pgagroal.conf ping`
- [ ] Is the backend reachable? `psql -h <backend> -p 5432 -U <user> -d <db>`
- [ ] Check `max_connections` -- is the pool full?
- [ ] Check `blocking_timeout` -- are clients timing out waiting for a slot?

### High latency

- [ ] Check pool utilization: `pgagroal-cli -c /etc/pgagroal/pgagroal.conf status`
- [ ] Is `max_connections` too low, causing queuing?
- [ ] Is `validation = foreground` adding per-connection overhead?
- [ ] Check backend query performance independently

### Connections not reused (pool not effective)

- [ ] Verify `pipeline` mode. `auto` selects `session` by default. For short-lived queries, `transaction` mode reuses connections more aggressively.
- [ ] Check `idle_timeout` -- too low means connections are closed before reuse
- [ ] Ensure clients are not setting session-level state that prevents reuse

### After backend restart, connections still fail

- [ ] Wait for `idle_timeout` to expire stale connections
- [ ] Or enable `validation = foreground` to catch them immediately
- [ ] Check pgagroal logs for connection errors
