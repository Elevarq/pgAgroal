# Install Elevarq pgAgroal from AWS Marketplace

Buyer-facing install guide for the **Elevarq pgAgroal** container product
(Helm chart delivery on Amazon EKS). This is the source for the listing's
usage instructions.

## Prerequisites

- An Amazon EKS cluster (or self-managed Kubernetes) and `kubectl` access.
- `helm` 3.8+ and the AWS CLI, configured for the subscribing account.
- A reachable PostgreSQL backend (Amazon RDS / Aurora, or self-managed).

## 1. Subscribe

Subscribe to **Elevarq pgAgroal** on AWS Marketplace. The product is free; the
subscription grants your account pull access to the Marketplace-managed ECR
repositories that hold the image and Helm chart.

## 2. Authenticate Helm to the Marketplace registry

```sh
aws ecr get-login-password --region <region> \
  | helm registry login --username AWS --password-stdin \
      709825985650.dkr.ecr.us-east-1.amazonaws.com
```

## 3. Configure a values file

Elevarq pgAgroal is configured through the chart's values. At minimum, point it
at your PostgreSQL backend and provide credentials (required — the v1.4.2
default does not pass unknown users through to the backend):

```yaml
# pgagroal-values.yaml
postgresql:
  host: <postgres-host>      # e.g. my-db.abc123.us-east-1.rds.amazonaws.com
  port: 5432

credentials:
  username: <app-user>
  password: <app-password>
  # ...or reference an existing Secret (keys: PG_USERNAME, PG_PASSWORD):
  # existingSecret: my-pg-credentials

pgagroal:
  maxConnections: 100        # pooled connections
  logLevel: info

# Optional: expose the built-in Prometheus metrics port
metrics:
  enabled: false
```

The full set of configurable values (probes, resources, PDB, security
contexts, observability sidecar) is documented in the
[project README](https://github.com/Elevarq/pgAgroal).

## 4. Install

```sh
helm install pgagroal \
  oci://709825985650.dkr.ecr.us-east-1.amazonaws.com/elevarq/elevarq-pgagroal-chart \
  --version 1.3.0 \
  -n pgagroal --create-namespace \
  -f pgagroal-values.yaml
```

## 5. Connect your applications

Point applications at the `pgagroal` Service on port **6432** (instead of
connecting to PostgreSQL directly):

```
postgresql://<app-user>@pgagroal.pgagroal.svc.cluster.local:6432/<database>
```

pgagroal pools and multiplexes those connections to the backend defined in
`postgresql.host`.

## Security posture

The image runs **non-root** (UID 1000) with **all Linux capabilities dropped**,
a **read-only root filesystem**, and **seccomp RuntimeDefault**. It is
multi-arch (linux/amd64 + linux/arm64). The upstream `ghcr.io` image is
cosign-signed with SBOM and SLSA provenance; the Marketplace copy is scanned by
AWS on ingestion. See
[`docs/security/`](https://github.com/Elevarq/pgAgroal/tree/main/docs) and
[`SECURITY.md`](https://github.com/Elevarq/pgAgroal/blob/main/SECURITY.md).

## Support

Community support: GitHub Issues at https://github.com/Elevarq/pgAgroal.
