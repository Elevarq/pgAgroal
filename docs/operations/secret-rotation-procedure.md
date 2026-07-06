# Credential Rotation Procedure

How to rotate PostgreSQL credentials used by pgagroal without downtime.

## Context

Since v1.4.0 the shipped default is `allow_unknown_users = false`, so pgagroal
admits only users it has registered (via PG_USERNAME/PG_PASSWORD), written to
`/etc/pgagroal/pgagroal_users.conf` at container startup. Rotation then
requires a pod restart to regenerate that file (see the registered-user
procedure below).

If you set `allow_unknown_users = true` (transparent pooling), pgagroal passes
credentials through to PostgreSQL without maintaining its own user store, and
rotation only requires updating the PostgreSQL password and ensuring clients
use the new one.

## Docker Compose

The compose file carries no credential values: it interpolates
`POSTGRES_PASSWORD` / `PGEXPORTER_PASSWORD` from the environment or the
local `.env` file (gitignored; see `.env.example`).

1. Change the password in PostgreSQL:

```sql
ALTER USER testuser WITH PASSWORD '<new-password>';
```

2. Update the value in `.env` (or the exported variable) — never in a
   tracked file:

```bash
# .env
POSTGRES_PASSWORD=<new-password>
```

3. If PG_USERNAME/PG_PASSWORD are set on the pgagroal service, restart it
   to pick up the new value:

```bash
docker compose up -d pgagroal     # recreates with new env
```

4. Verify:

```bash
PGPASSWORD='<new-password>' psql -h localhost -p 6432 -U testuser -d testdb -c 'SELECT 1;'
```

## Kubernetes / Helm

### With allow_unknown_users = true (transparent pooling; not the v1.4.0 default)

Existing pooled connections continue using the old credentials until they expire (`idle_timeout`). New connections from clients must use the new password.

1. Rotate the password in PostgreSQL / RDS:

```sql
ALTER USER app_user WITH PASSWORD '<new-password>';
```

2. Update the Kubernetes Secret:

```bash
kubectl create secret generic pgagroal-pg-credentials \
  --from-literal=PG_USERNAME=app_user \
  --from-literal=PG_PASSWORD='<new-password>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

3. If using PG_USERNAME/PG_PASSWORD env vars (registered users), restart pods to pick up the new secret values:

```bash
kubectl rollout restart deployment pgagroal -n pgagroal
```

4. Verify:

```bash
kubectl -n pgagroal port-forward svc/pgagroal 6432:6432 &
PGPASSWORD='<new-password>' psql -h 127.0.0.1 -p 6432 -U app_user -d mydb -c 'SELECT 1;'
```

### With External Secrets Operator

If you use ExternalSecret pointing to AWS Secrets Manager:

1. Rotate the secret in Secrets Manager
2. Wait for `refreshInterval` (or trigger a manual sync)
3. Restart the deployment to pick up new values:

```bash
kubectl rollout restart deployment pgagroal -n pgagroal
```

### Minimizing Disruption

- Use a rolling restart (`kubectl rollout restart`) so that the PDB keeps at least one pod available
- Set `idle_timeout` to a value lower than your rotation interval so stale backend connections are cleaned up
- After rotation, monitor for authentication errors in pgagroal logs:
  ```bash
  kubectl -n pgagroal logs -l app.kubernetes.io/name=pgagroal --since=5m | grep -i auth
  ```

## Rollback

If the new password is wrong and connections start failing:

1. Revert the PostgreSQL password:
   ```sql
   ALTER USER app_user WITH PASSWORD '<old-password>';
   ```
2. Revert the Kubernetes Secret
3. Restart pods if PG_USERNAME/PG_PASSWORD are in use
