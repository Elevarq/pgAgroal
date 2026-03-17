# EKS Deployment Guide

Step-by-step guide for deploying pgagroal on AWS EKS.

## Prerequisites

- AWS CLI configured
- `kubectl` pointing at your EKS cluster
- Helm 3 installed
- Docker for building the image
- An RDS PostgreSQL instance

## 1. Build and Push the Image to ECR

```bash
# Create ECR repository (once)
aws ecr create-repository --repository-name pgagroal --region eu-west-1

# Build
make build

# Tag and push
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=eu-west-1
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

aws ecr get-login-password --region ${REGION} \
  | docker login --username AWS --password-stdin ${REGISTRY}

docker tag pgagroal:2.0.2 ${REGISTRY}/pgagroal:2.0.2
docker push ${REGISTRY}/pgagroal:2.0.2
```

## 2. Create the Credentials Secret

Create the secret **before** installing the chart (when using `credentials.existingSecret`):

```bash
kubectl create secret generic pgagroal-pg-credentials \
  --from-literal=PG_USERNAME=app_user \
  --from-literal=PG_PASSWORD='<password>'
```

For production, use Sealed Secrets or AWS Secrets Manager with External Secrets Operator:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: pgagroal-pg-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: pgagroal-pg-credentials
  data:
    - secretKey: PG_USERNAME
      remoteRef:
        key: prod/pgagroal
        property: username
    - secretKey: PG_PASSWORD
      remoteRef:
        key: prod/pgagroal
        property: password
```

## 3. Configure values

Copy and edit the example values file:

```bash
cp helm/pgagroal/values-eks-example.yaml my-values.yaml
```

Key fields to change:

| Field | Set to |
|---|---|
| `image.repository` | Your ECR URI |
| `postgresql.host` | Your RDS endpoint |
| `credentials.existingSecret` | The secret name from step 2 |
| `serviceAccount.annotations` | Your IRSA role ARN (for ECR pull) |
| `pgagroal.maxConnections` | Match RDS `max_connections` budget |

## 4. Install with Helm

```bash
helm install pgagroal ./helm/pgagroal -f my-values.yaml -n pgagroal --create-namespace
```

Verify:

```bash
kubectl -n pgagroal get pods
kubectl -n pgagroal logs -l app.kubernetes.io/name=pgagroal
```

## 5. Test Connectivity

```bash
# Port-forward
kubectl -n pgagroal port-forward svc/pgagroal 6432:6432 &

# Connect
psql -h 127.0.0.1 -p 6432 -U app_user -d mydb -c 'SELECT 1;'
```

## 6. Upgrades

```bash
# Change image.tag or pgagroal settings in my-values.yaml, then:
helm upgrade pgagroal ./helm/pgagroal -f my-values.yaml -n pgagroal
```

The Deployment has a `checksum/config` annotation on the ConfigMap content, so config changes automatically trigger a rolling restart.

## 7. Monitoring

With `metrics.enabled: true`, pgagroal exposes Prometheus metrics on port 9187. The EKS example values include Prometheus pod annotations. If you use the Prometheus Operator, create a ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: pgagroal
  namespace: pgagroal
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: pgagroal
  endpoints:
    - port: metrics
      interval: 15s
```

## Security Notes

- The pod runs as **UID 1000** (non-root) with `allowPrivilegeEscalation: false`
- All Linux capabilities are dropped
- `seccompProfile: RuntimeDefault` is enabled
- `readOnlyRootFilesystem: true` is set; `/etc/pgagroal` and `/tmp` use emptyDir volumes
- `automountServiceAccountToken: false` on the ServiceAccount
- Credentials are injected via Kubernetes Secrets, never baked into the image
- Consider adding a NetworkPolicy to restrict traffic to only the application namespace and PostgreSQL CIDR

## Troubleshooting

| Symptom | Check |
|---|---|
| Pod stuck in `Init` | `kubectl logs <pod> -c copy-config-templates` |
| CrashLoopBackOff | `kubectl logs <pod> -c pgagroal` -- usually a backend connectivity issue |
| Readiness probe failing | Verify `postgresql.host` is reachable from the pod network |
| Connection refused on 6432 | Check Security Groups allow traffic between EKS nodes and RDS |
