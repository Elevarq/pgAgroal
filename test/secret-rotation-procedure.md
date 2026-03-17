# Credential Rotation Procedure

How to rotate PostgreSQL credentials used by pgagroal without downtime.

## Context

pgagroal uses `allow_unknown_users = true` by default, meaning it passes credentials through to PostgreSQL without maintaining its own user store. This simplifies rotation: you only need to update the PostgreSQL password and ensure clients use the new one.

If you have registered users via `pgagroal-admin` (PG_USERNAME/PG_PASSWORD env vars), those are written to `/etc/pgagroal/pgagroal_users.conf` at container startup. Rotation requires a pod restart to regenerate this file.

## Docker Compose

1. Change the password in PostgreSQL:

```sql
ALTER USER testuser WITH PASSWORD 'newpassword';
```

2. Update `docker-compose.yml` environment variables:

```yaml
environment:
  POSTGRES_PASSWORD: newpassword  # postgres service
```

```yaml
environment:
  PGPASSWORD: newpassword          # test-client
```

3. If PG_USERNAME/PG_PASSWORD are set on the pgagroal service, update them and restart:

```bash
docker compose up -d pgagroal     # recreates with new env
```

4. Verify:

```bash
PGPASSWORD=newpassword psql -h localhost -p 6432 -U testuser -d testdb -c 'SELECT 1;'
```

## Kubernetes / Helm

### With allow_unknown_users = true (default)

Existing pooled connections continue using the old credentials until they expire (`idle_timeout`). New connections from clients must use the new password.

1. Rotate the password in PostgreSQL / RDS:

```sql
ALTER USER app_user WITH PASSWORD 'newpassword';
```

2. Update the Kubernetes Secret:

```bash
kubectl create secret generic pgagroal-pg-credentials \
  --from-literal=PG_USERNAME=app_user \
  --from-literal=PG_PASSWORD='newpassword' \
  --dry-run=client -o yaml | kubectl apply -f -
```

3. If using PG_USERNAME/PG_PASSWORD env vars (registered users), restart pods to pick up the new secret values:

```bash
kubectl rollout restart deployment pgagroal -n pgagroal
```

4. Verify:

```bash
kubectl -n pgagroal port-forward svc/pgagroal 6432:6432 &
PGPASSWORD=newpassword psql -h 127.0.0.1 -p 6432 -U app_user -d mydb -c 'SELECT 1;'
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
   ALTER USER app_user WITH PASSWORD 'oldpassword';
   ```
2. Revert the Kubernetes Secret
3. Restart pods if PG_USERNAME/PG_PASSWORD are in use
