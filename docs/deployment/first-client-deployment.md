# First Client Deployment

Step-by-step guide for deploying pgagroal to a client EKS cluster for the first time.

## Prerequisites

Before starting, confirm:

- [ ] `kubectl` is configured and pointing at the target EKS cluster
- [ ] `helm` v3 is installed locally
- [ ] The pgagroal container image has been pushed to ECR (see [docs/eks-deployment.md](eks-deployment.md) steps 1-2)
- [ ] You know the ECR image URI and tag (e.g. `123456789012.dkr.ecr.eu-west-1.amazonaws.com/pgagroal:2.0.2`)
- [ ] You know the PostgreSQL/RDS endpoint and port
- [ ] You have the PostgreSQL credentials (username + password)
- [ ] EKS nodes can reach the RDS instance (Security Groups, VPC peering, etc.)

## Step 1: Create the namespace

```bash
kubectl create namespace pgagroal
```

## Step 2: Create the credentials secret

```bash
kubectl -n pgagroal create secret generic pgagroal-pg-credentials \
  --from-literal=PG_USERNAME='<pg_username>' \
  --from-literal=PG_PASSWORD='<pg_password>'
```

Verify:

```bash
kubectl -n pgagroal get secret pgagroal-pg-credentials
```

## Step 3: Prepare values file

Copy the appropriate example and fill in the client-specific values:

```bash
# For a standard deployment:
cp helm/pgagroal/values-client-example.yaml client-values.yaml

# For a quick minimal deployment:
cp helm/pgagroal/values-client-minimal.yaml client-values.yaml
```

Edit `client-values.yaml` -- the fields you **must** change:

| Field | What to set |
|---|---|
| `image.repository` | ECR URI: `<ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com/pgagroal` |
| `postgresql.host` | RDS endpoint: `mydb.cluster-xxx.region.rds.amazonaws.com` |
| `credentials.existingSecret` | `pgagroal-pg-credentials` (from step 2) |

Optional but recommended:

| Field | When to change |
|---|---|
| `pgagroal.maxConnections` | Must fit within RDS `max_connections / replicas` |
| `replicaCount` | 2 minimum for production, 3 for multi-AZ |
| `resources` | Adjust based on expected connection count |

## Step 4: Install

```bash
helm install pgagroal helm/pgagroal/ \
  -f client-values.yaml \
  -n pgagroal
```

Expected output:

```
NAME: pgagroal
NAMESPACE: pgagroal
STATUS: deployed
```

## Step 5: Verify pods are running

```bash
kubectl -n pgagroal get pods -w
```

Wait until all pods show `Running` and `READY 1/1`. This typically takes 10-30 seconds.

If pods are not ready after 60 seconds, see [Troubleshooting](#troubleshooting) below.

## Step 6: Verify the service

```bash
kubectl -n pgagroal get svc
```

Expected: a `ClusterIP` service on port 6432.

## Step 7: Smoke test from inside the cluster

Launch a temporary pod and connect through pgagroal:

```bash
kubectl -n pgagroal run pgagroal-smoke-test \
  --rm -it --restart=Never \
  --image=postgres:17.4-bookworm \
  --env="PGPASSWORD=<pg_password>" \
  -- psql -h pgagroal -p 6432 -U <pg_username> -d <database> -c "SELECT 1 AS ok;"
```

Expected output:

```
 ok
----
  1
(1 row)
```

The pod deletes itself after the command completes (`--rm`).

## Step 8: Post-deployment verification

Run through [docs/post-deployment-verification.md](post-deployment-verification.md) -- it covers release checks, log inspection, restart recovery, resource review, and a final acceptance checklist.

Complete it before handing off to the client. A quick summary is also in the [Operational Acceptance Checklist](#operational-acceptance-checklist) below.

## Upgrades

After modifying `client-values.yaml`:

```bash
helm upgrade pgagroal helm/pgagroal/ \
  -f client-values.yaml \
  -n pgagroal
```

Config changes (maxConnections, logLevel, etc.) automatically trigger a rolling restart via the `checksum/config` annotation.

## Rollback

If something goes wrong after an upgrade:

```bash
# List revisions
helm history pgagroal -n pgagroal

# Roll back to previous revision
helm rollback pgagroal <revision> -n pgagroal

# Or roll back to the immediately previous version
helm rollback pgagroal -n pgagroal
```

## Uninstall

```bash
helm uninstall pgagroal -n pgagroal
kubectl delete namespace pgagroal
```

This removes all pgagroal resources. The credentials secret is deleted with the namespace.

---

## Operational Acceptance Checklist

Complete this after initial deployment and before client handoff.

### Infrastructure

- [ ] All pods are `Running` and `READY 1/1`:
  ```bash
  kubectl -n pgagroal get pods
  ```

- [ ] No unexpected restarts (RESTARTS column = 0):
  ```bash
  kubectl -n pgagroal get pods
  ```

- [ ] Service is created and has a ClusterIP:
  ```bash
  kubectl -n pgagroal get svc pgagroal
  ```

- [ ] PodDisruptionBudget is active:
  ```bash
  kubectl -n pgagroal get pdb
  ```

### Connectivity

- [ ] Connection through pgagroal succeeds (smoke test from step 7)

- [ ] Application namespace can reach the pgagroal service:
  ```bash
  # From a pod in the application namespace:
  psql -h pgagroal.pgagroal.svc.cluster.local -p 6432 -U <user> -d <db> -c "SELECT 1;"
  ```

### Resilience

- [ ] Bad password is rejected cleanly (pgagroal stays healthy):
  ```bash
  kubectl -n pgagroal run auth-test \
    --rm -it --restart=Never \
    --image=postgres:17.4-bookworm \
    --env="PGPASSWORD=wrong" \
    -- psql -h pgagroal -p 6432 -U <pg_username> -d <database> -c "SELECT 1;" 2>&1 || true
  # Expect: authentication error
  # Then verify pods are still Running:
  kubectl -n pgagroal get pods
  ```

- [ ] Pods recover if restarted:
  ```bash
  kubectl -n pgagroal delete pod -l app.kubernetes.io/name=pgagroal
  # Wait for new pods, then re-run smoke test
  ```

### Resources

- [ ] CPU and memory usage are within expected bounds:
  ```bash
  kubectl -n pgagroal top pods
  ```

- [ ] No OOMKilled events:
  ```bash
  kubectl -n pgagroal get events --sort-by=.lastTimestamp | grep -i oom
  ```

### Logs

- [ ] Logs show clean startup (no errors):
  ```bash
  kubectl -n pgagroal logs -l app.kubernetes.io/name=pgagroal --tail=20
  ```

---

## Troubleshooting

### Pods stuck in Init

The init container copies config templates. Check its logs:

```bash
kubectl -n pgagroal logs <pod-name> -c copy-config-templates
```

Common cause: image pull failure. Verify ECR access:

```bash
kubectl -n pgagroal describe pod <pod-name> | grep -A5 "Events"
```

### Pods in CrashLoopBackOff

Check pgagroal logs:

```bash
kubectl -n pgagroal logs <pod-name> -c pgagroal --previous
```

Common causes:
- Wrong `postgresql.host` (DNS resolution failure)
- Config syntax error (check envsubst output in logs)

### Readiness probe failing

The readiness probe runs `pgagroal-cli ping`. If it fails, the pgagroal daemon is not running:

```bash
kubectl -n pgagroal exec <pod-name> -c pgagroal -- pgagroal-cli -c /etc/pgagroal/pgagroal.conf ping
```

### Connection refused

1. Is the service resolving?
   ```bash
   kubectl -n pgagroal get endpoints pgagroal
   ```

2. Is RDS reachable from the pod network?
   ```bash
   kubectl -n pgagroal run net-test --rm -it --restart=Never \
     --image=postgres:17.4-bookworm \
     -- pg_isready -h <rds-endpoint> -p 5432
   ```

3. Check Security Groups allow TCP 5432 from EKS node CIDR to the RDS instance.

### Image pull errors

If using IRSA for ECR access, verify the ServiceAccount annotation:

```bash
kubectl -n pgagroal get sa pgagroal -o yaml | grep eks.amazonaws.com
```

If using imagePullSecrets, verify the secret exists:

```bash
kubectl -n pgagroal get secret <pull-secret-name>
```
