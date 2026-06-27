# Failure Modes Reference

Documented failure scenarios for pgagroal in this container setup. Each section describes the trigger, observed behavior, operator-facing symptoms, and recovery path.

## 1. Backend Unavailable on Startup

**Trigger**: pgagroal starts before PostgreSQL is reachable (DNS failure, backend not yet provisioned, network partition).

**Behavior**:
- pgagroal starts normally -- the daemon process initializes and binds to its port
- `pgagroal-cli ping` reports the daemon as alive
- Client connections that arrive are forwarded to the backend; since the backend is unreachable, pgagroal returns a connection error to the client immediately (or after `blocking_timeout` if configured)
- pgagroal does NOT crash or exit

**Operator symptoms**:
- Docker health check passes (daemon alive)
- Client applications log connection errors
- pgagroal logs show backend connection failures

**Recovery**: automatic. Once the backend becomes reachable, new client connections succeed without restart.

**Tested by**: `test/resilience/startup-failure-test.sh`

**Kubernetes note**: this is normal during pod startup. The readiness probe (`pgagroal-cli ping`) will pass even if the backend is not yet available. This is intentional -- the pooler should not be killed during backend provisioning. Applications should implement connection retry logic.

## 2. Backend Restart During Operation

**Trigger**: PostgreSQL restarts (maintenance, failover, RDS reboot).

**Behavior**:
- Existing pooled connections become invalid (TCP RST or timeout)
- Clients using a stale pooled connection receive a connection error
- pgagroal detects broken connections when clients attempt to use them
- New backend connections are established once PostgreSQL is back

**Operator symptoms**:
- Brief spike in client-side connection errors
- pgagroal logs show backend disconnect/reconnect messages
- `pgagroal-cli ping` continues to pass throughout

**Recovery**: automatic within seconds of backend returning.

**Tested by**: `test/resilience/backend-restart-test.sh`

**Mitigation**: set `validation = foreground` to check connections before handing them to clients. This prevents serving stale connections at the cost of one extra round-trip per checkout.

## 3. Invalid Credentials

**Trigger**: client connects with wrong password, or pgagroal user is not configured in PostgreSQL.

Since v1.4.0 the shipped default is `allow_unknown_users = false`, so an
unknown user is rejected by pgagroal at the frontend and the backend is never
contacted. The pass-through behavior below applies when you set
`allow_unknown_users = true` (transparent pooling):

**Behavior** (with `allow_unknown_users = true`, transparent pooling):
- pgagroal passes the credentials through to PostgreSQL
- PostgreSQL rejects the authentication
- pgagroal returns the authentication error to the client
- pgagroal itself stays healthy

**Operator symptoms**:
- Client receives `FATAL: password authentication failed for user "xxx"`
- pgagroal health check continues passing
- pgagroal logs may show the authentication failure (at `info` or `debug` level)

**Recovery**: client retries with correct credentials. No pooler restart needed.

**Tested by**: `test/validation/invalid-credentials-test.sh`

**Important**: bad credential attempts do NOT poison the connection pool. Subsequent connections with correct credentials work normally.

## 4. DNS / Hostname Resolution Failure

**Trigger**: `PG_BACKEND_HOST` resolves to nothing (typo, DNS outage, service not registered).

**Behavior**:
- pgagroal starts normally (does not resolve the backend hostname at startup)
- Client connections fail with a connection error
- If DNS recovers, new connections succeed automatically

**Operator symptoms**:
- Same as "backend unavailable on startup"
- pgagroal logs may show `getaddrinfo` or similar resolution errors

**Recovery**: fix DNS or hostname configuration. No pgagroal restart required unless the hostname was baked into the config (which it is via envsubst at startup). If the env var was wrong, restart the container with the corrected value.

**Kubernetes note**: if using a Kubernetes Service name as `postgresql.host`, ensure the Service exists in the same namespace or use a fully-qualified name (`svc.namespace.svc.cluster.local`).

## 5. Secret Rotation Timing

**Trigger**: PostgreSQL password is changed but pgagroal's registered user (if any) still has the old password.

**Behavior** (two scenarios):

### allow_unknown_users = true (transparent pooling; not the v1.4.0 default)
- pgagroal does not validate credentials itself -- it passes them through
- Clients that send the NEW password succeed immediately
- Clients that send the OLD password fail with auth error
- No pooler restart needed for the credential pass-through

### Registered user via PG_USERNAME/PG_PASSWORD
- The registered user's credentials are stored in `pgagroal_users.conf` at container startup
- If the PostgreSQL password changes but the container's env var still has the old value, pgagroal may reject connections (if it validates internally) or pass through incorrect credentials
- **Fix**: update the Kubernetes Secret and restart the pod (rolling restart via `kubectl rollout restart`)

**Operator symptoms**:
- Authentication errors in client applications
- pgagroal stays healthy (daemon alive)

**Recovery**: see [secret-rotation-procedure.md](secret-rotation-procedure.md)

**Window of risk**: between PostgreSQL password change and pod restart. Keep this window small. In Kubernetes, automate with External Secrets Operator + rolling restart annotation.

## 6. Pool Corruption After Abnormal Client Disconnect

**Trigger**: a client process crashes, is killed, or has its TCP connection severed mid-session (e.g. application OOMKill, network partition, Ctrl+C during `pgbench`).

**Behavior**:
- The pooled backend connection may not be properly returned to the pool
- In some cases, pgagroal continues opening new backend connections beyond the configured `max_connections` limit
- Subsequent client connections may see 0 throughput or indefinite hangs
- `pgagroal-cli status` may show connection counts exceeding the configured maximum
- pgagroal does NOT crash -- the daemon stays running

**Operator symptoms**:
- Application reports connection timeouts or 0 TPS
- `pg_stat_activity` on the backend shows more connections than expected
- Health check (`pgagroal-cli ping`) continues to pass
- Logs may not show any explicit error

**Recovery**: **restart the pgagroal pod**. There is no in-place recovery. In Kubernetes:

```bash
kubectl -n pgagroal rollout restart deployment pgagroal
```

**Upstream reference**: [pgagroal#503](https://github.com/pgagroal/pgagroal/issues/503)

**Mitigation**:
- Ensure application code uses connection timeouts (`connect_timeout`, `statement_timeout`)
- Monitor backend connection count via `pg_stat_activity`; alert if it exceeds `max_connections * replicas`
- The PDB ensures at least one replica stays available during a rolling restart

**Early detection** (see [Monitoring for Pool Corruption](#monitoring-for-pool-corruption) below)

## 7. CLI Management Commands Destabilize Running Daemon

**Trigger**: running `pgagroal-cli conf set` or `pgagroal-cli reload` against a running pgagroal instance.

**Behavior**:
- The configuration reload path has known bugs that cause network binding conflicts ("Address already in use") and repeated "Bad file descriptor" errors in the accept loop
- The CLI management command forks a child process that can corrupt the parent's event loop
- The daemon may become partially or fully unresponsive to new connections

**Operator symptoms**:
- Log spam: `accept: Bad file descriptor` or `Address already in use`
- New connections fail intermittently or completely
- Health check may still pass (daemon process alive, management socket responsive)

**Recovery**: restart the pod.

**Upstream references**: [pgagroal#767](https://github.com/pgagroal/pgagroal/issues/767), [pgagroal#750](https://github.com/pgagroal/pgagroal/issues/750)

**Rule**: **never use `pgagroal-cli conf set` or `pgagroal-cli reload` in production**. Use rolling restart for all configuration changes. The Helm chart's `checksum/config` annotation triggers this automatically on `helm upgrade`.

## 8. Connection Pool Exhaustion

**Trigger**: more simultaneous client connections than `max_connections`.

**Behavior**:
- New client connections block waiting for a pool slot
- If no slot frees up within `blocking_timeout` (default 30s), the client gets a timeout error
- pgagroal stays healthy

**Operator symptoms**:
- Client applications report connection timeouts
- `pgagroal-cli status` shows pool at capacity
- pgagroal logs show blocking/timeout messages

**Recovery**:
- Increase `max_connections` (requires container restart)
- Scale replicas horizontally (each gets its own pool)
- Fix application connection leaks (connections not being closed)

**Sizing rule**: `max_connections` should be >= peak concurrent application connections per pooler replica, but <= PostgreSQL's `max_connections / replicas`.

## 9. Replica Scaling Caveats

**Trigger**: scaling pgagroal replicas without adjusting `max_connections`.

**Behavior**:
- Each replica maintains an independent pool
- Total backend connections = `replicas * max_connections`
- If this exceeds PostgreSQL's `max_connections`, backend connections start failing

**Operator symptoms**:
- pgagroal logs: `too many connections for role "xxx"`
- Some replicas work, others fail intermittently
- Clients see sporadic connection errors

**Recovery**: reduce `max_connections` per replica or increase PostgreSQL's `max_connections`.

**Formula**:
```
pgagroal max_connections <= (PG max_connections - superuser_reserved - other_services) / replicas
```

## Summary Matrix

| Failure | pgagroal crashes? | Health check passes? | Auto-recovery? | Action needed? |
|---|---|---|---|---|
| Backend down on startup | No | Yes | Yes (when backend up) | None |
| Backend restart | No | Yes | Yes (seconds) | None |
| Invalid credentials | No | Yes | N/A (client error) | Fix client creds |
| DNS failure | No | Yes | Yes (when DNS up) | Fix DNS if permanent |
| Secret rotation | No | Yes | Partial | Restart pod if registered user |
| Pool corruption (abnormal disconnect) | No | Yes | **No** | Restart pod |
| CLI conf set / reload | No | Yes | **No** | Restart pod; never use in production |
| Pool exhaustion | No | Yes | Yes (when clients release) | Scale up or fix leaks |
| Replica over-scaling | No | Yes | No | Reduce max_connections |

---

## Monitoring for Pool Corruption

Pool corruption (failure mode #6) is silent -- the health check passes and logs may show nothing. Early detection requires monitoring the backend directly.

### Signal: backend connection count exceeds expected maximum

The expected maximum backend connections from pgagroal is:

```
expected_max = max_connections * replicas
```

If `pg_stat_activity` count exceeds this, the pool is likely corrupted.

### Query to run against the PostgreSQL backend

```sql
SELECT
    count(*) AS total_backend_connections,
    count(*) FILTER (WHERE state = 'active') AS active,
    count(*) FILTER (WHERE state = 'idle') AS idle,
    count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_tx
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND usename NOT IN ('rdsadmin', 'postgres');
```

### Alert rule (Prometheus / CloudWatch)

Alert if `total_backend_connections > max_connections * replicas` for more than 2 minutes:

```
pg_stat_activity_count{state!="superuser"} > (pgagroal_max_connections * pgagroal_replica_count) * 1.1
```

If the alert fires: `kubectl -n pgagroal rollout restart deployment pgagroal`.

### Sampling script

For ad-hoc monitoring, use the included sampling script:

```bash
PGPASSWORD=<password> scripts/sampling/connection-count.sh \
  --host <rds-endpoint> --port 5432 --user <user> --db <database> \
  --interval 5 --duration 300 --output conn_count.csv
```

Review the CSV: if the `total` column trends upward beyond `max_connections * replicas`, corruption is likely.

---

## Production Defaults Summary

These defaults are applied in `pgagroal.conf.template` and the Helm ConfigMap:

| Setting | Value | Why |
|---|---|---|
| `ev_backend` | `epoll` | Avoids io_uring segfault ([pgagroal#762](https://github.com/pgagroal/pgagroal/issues/762)). Temporary until upstream fix. |
| `pipeline` | `auto` (session mode) | Transaction mode requires per-app validation. Session mode is safe by default. |
| `validation` | `off` | Foreground validation adds latency. Enable if stale connections are a problem. |
| `blocking_timeout` | `30` | Clients wait up to 30s for a pool slot before timeout. |
| `idle_timeout` | `600` | Idle connections closed after 10 minutes. |

**Never** use `pgagroal-cli conf set` or `pgagroal-cli reload` in production. Use rolling restart.
