# Post-Deployment Verification

Run through this guide after `helm install` completes. Every command is copy-pasteable. Replace `<placeholders>` with your actual values.

A deployment is **successful** when all sections below pass. If any step fails, jump to [Common Misconfigurations](#common-misconfigurations) at the bottom.

## 1. Release verification

Confirm Helm recorded the release:

```bash
helm list -n pgagroal
```

Expected: `STATUS = deployed`, chart version matches `0.1.0`, app version matches `2.0.2`.

Check the deployed image:

```bash
kubectl -n pgagroal get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

Expected: every pod shows your ECR URI with tag `2.0.2`.

## 2. Pod readiness

```bash
kubectl -n pgagroal get pods
```

Expected for every pod:

| Column | Value |
|---|---|
| STATUS | `Running` |
| READY | `1/1` |
| RESTARTS | `0` |

If any pod shows `0/1`, `Init:*`, or `CrashLoopBackOff`, check:

```bash
# Init container logs
kubectl -n pgagroal logs <pod> -c copy-config-templates

# Main container logs (current or previous crash)
kubectl -n pgagroal logs <pod> -c pgagroal
kubectl -n pgagroal logs <pod> -c pgagroal --previous
```

Describe the pod for events (image pull errors, scheduling failures):

```bash
kubectl -n pgagroal describe pod <pod>
```

## 3. Service verification

```bash
kubectl -n pgagroal get svc pgagroal
```

Expected: `TYPE = ClusterIP`, `PORT(S) = 6432/TCP`.

Confirm endpoints are populated (one IP per ready pod):

```bash
kubectl -n pgagroal get endpoints pgagroal
```

If endpoints are empty, no pods matched the service selector. Check labels:

```bash
kubectl -n pgagroal get pods --show-labels
```

## 4. In-cluster connection test

Run a throwaway pod and connect through pgagroal to the backend:

```bash
kubectl -n pgagroal run verify-conn \
  --rm -it --restart=Never \
  --image=postgres:17.4-bookworm \
  --env="PGPASSWORD=<pg_password>" \
  -- psql -h pgagroal -p 6432 -U <pg_username> -d <database> \
     -c "SELECT current_database(), current_user, version();"
```

Expected: one row with the database name, username, and PostgreSQL version from the backend.

Test cross-namespace access (from the application namespace):

```bash
kubectl -n <app-namespace> run verify-cross-ns \
  --rm -it --restart=Never \
  --image=postgres:17.4-bookworm \
  --env="PGPASSWORD=<pg_password>" \
  -- psql -h pgagroal.pgagroal.svc.cluster.local -p 6432 \
     -U <pg_username> -d <database> -c "SELECT 1 AS ok;"
```

## 5. Log inspection

Check every replica has a clean startup:

```bash
kubectl -n pgagroal logs -l app.kubernetes.io/name=pgagroal --tail=30
```

Expected: `pgagroal: 2.0.2 started on *:6432` with no `ERROR` or `FATAL` lines.

Search for errors:

```bash
kubectl -n pgagroal logs -l app.kubernetes.io/name=pgagroal --since=10m | grep -iE 'error|fatal|warn' || echo "No errors found"
```

## 6. Restart and recovery verification

### Pod restart recovery

Delete one pod and confirm the replacement comes up healthy:

```bash
POD=$(kubectl -n pgagroal get pods -o name | head -1)
kubectl -n pgagroal delete ${POD}

# Watch replacement pod come up
kubectl -n pgagroal get pods -w
```

Expected: new pod reaches `Running 1/1` within 30 seconds. PDB keeps other replicas available during the restart.

Re-run the connection test from step 4 to confirm connectivity is restored.

### Bad-credential resilience

Verify pgagroal rejects wrong passwords without crashing:

```bash
kubectl -n pgagroal run bad-creds-test \
  --rm -it --restart=Never \
  --image=postgres:17.4-bookworm \
  --env="PGPASSWORD=deliberately_wrong_password" \
  -- psql -h pgagroal -p 6432 -U <pg_username> -d <database> \
     -c "SELECT 1;" 2>&1; true
```

Expected: authentication error from psql. Then confirm pods are unaffected:

```bash
kubectl -n pgagroal get pods
```

RESTARTS should still be 0.

## 7. Resource usage

```bash
kubectl -n pgagroal top pods
```

Baseline expectations (idle / light load):

| Metric | Expected |
|---|---|
| CPU | < 50m per pod |
| Memory | < 40Mi per pod |

Check for OOMKilled or resource pressure events:

```bash
kubectl -n pgagroal get events --sort-by=.lastTimestamp | grep -iE 'oom|evict|backoff|unhealthy' || echo "No concerning events"
```

Check PDB status:

```bash
kubectl -n pgagroal get pdb
```

Expected: `ALLOWED DISRUPTIONS >= 1`.

## 8. Helm values verification

Confirm the deployed values match what was intended:

```bash
helm get values pgagroal -n pgagroal
```

Review for correctness: image repo/tag, postgresql.host, maxConnections, replicaCount.

---

## Common Misconfigurations

| Symptom | Likely cause | Fix |
|---|---|---|
| Pods stuck in `Init:ImagePullBackOff` | ECR URI wrong or IRSA role missing | Check `image.repository` in values; verify SA annotation with `kubectl -n pgagroal get sa pgagroal -o yaml` |
| Pods `CrashLoopBackOff` with log `connection refused` | RDS endpoint wrong or unreachable | Verify `postgresql.host`; test with `pg_isready -h <endpoint> -p 5432` from a pod |
| Pods `CrashLoopBackOff` with log `getaddrinfo` | DNS resolution failure | Check `postgresql.host` is a valid FQDN; check VPC DNS settings |
| Pods `Running` but connection test fails with auth error | Wrong secret values | Recreate secret with correct PG_USERNAME/PG_PASSWORD |
| Pods `Running` but connection test times out | Security Group blocks 5432 from EKS nodes to RDS | Add inbound rule on RDS SG for EKS node CIDR |
| Pods `Running` but endpoints are empty | Label mismatch between Service and Deployment | Check `kubectl -n pgagroal get pods --show-labels` matches Service selector |
| `helm install` fails with `secret not found` | Credentials secret not created before install | Run `kubectl -n pgagroal create secret generic ...` first |
| Multiple pods on same node | No anti-affinity set | Use `values-client-example.yaml` which includes AZ-spread affinity |
| Pool exhaustion under load | `maxConnections` too low | Increase `pgagroal.maxConnections` (must fit within `RDS max_connections / replicas`) |

---

## Final Acceptance Checklist

Complete every item before signing off the deployment.

- [ ] `helm list -n pgagroal` shows status `deployed`
- [ ] All pods `Running`, `READY 1/1`, `RESTARTS 0`
- [ ] Service has populated endpoints
- [ ] In-cluster connection succeeds (step 4)
- [ ] Cross-namespace connection succeeds (step 4)
- [ ] Logs show clean startup, no errors (step 5)
- [ ] Pod restart produces a healthy replacement (step 6)
- [ ] Bad credentials rejected cleanly, no pod crash (step 6)
- [ ] CPU and memory within expected bounds (step 7)
- [ ] No OOMKilled or eviction events (step 7)
- [ ] PDB allows at least 1 disruption (step 7)
- [ ] Helm values match intended configuration (step 8)

**Deployment is accepted when all boxes are checked.**
