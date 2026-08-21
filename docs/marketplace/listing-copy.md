# AWS Marketplace listing copy — Elevarq pgAgroal

Canonical, paste-ready copy for the Elevarq pgAgroal AWS Marketplace
container listing. Keyed to **Elevarq packaging v1.4.5, bundling upstream
pgagroal 2.1.0**. Tracks [#55](https://github.com/Elevarq/pgAgroal/issues/55).

Heading text below is **sentence case** (only the first word and proper
nouns are capitalized) to match the portal listing style; the headings
mirror the portal fields.

> **Naming.** **Elevarq pgAgroal** is the product — this container image plus
> Helm chart. **pgagroal** (lowercase) is the upstream connection pooler it
> bundles. The two are spelled differently on purpose; do not "correct" one
> to the other. Use "Elevarq pgAgroal" for the product/brand and lowercase
> "pgagroal" for the pooler, its binaries, config, and the upstream project.

## Product title

Elevarq pgAgroal

## Short description

Production-ready, security-hardened pgagroal container for PostgreSQL:
restrictive shipped defaults, a non-root runtime, signed multi-arch images,
a Kubernetes Helm chart, and zero telemetry.

## Product overview

Elevarq pgAgroal is an open-source (BSD-3-Clause) production container image
for pgagroal, the high-performance connection pooler for PostgreSQL. It is
built from pinned upstream pgagroal 2.1.0 sources on a digest-pinned Debian
base, for secure, repeatable production deployments.

It ships hardened by default. The shipped pgagroal HBA accepts connections
only from a configurable source-address allowlist (the RFC1918 private
ranges by default) and always authenticates with scram-sha-256 — never a
`host all all all all` catch-all. Unknown users are not transparently passed
through to the backend (`allow_unknown_users` defaults to false). The Helm
chart enables a NetworkPolicy by default that denies ingress from outside
the release namespace, and the bundled compose example publishes the pooler
and metrics ports on loopback only.

The runtime runs as a non-root user (UID 1000), drops all Linux
capabilities, uses a read-only root filesystem, and defaults to the
RuntimeDefault seccomp profile. Multi-architecture images (linux/amd64 and
linux/arm64) are cosign-signed using GitHub OIDC and include an SBOM and
SLSA provenance. The Helm chart simplifies Amazon EKS deployment with
liveness and readiness probes, a PodDisruptionBudget, least-privilege
security contexts, and optional Prometheus metrics. Elevarq pgAgroal
contains no telemetry and sends no data outside your environment.

## Highlights

(AWS allows up to 3.)

1. Hardened shipped defaults: scram-sha-256 HBA source-address allowlist (no
   catch-all), no transparent unknown-user passthrough, and a default-on
   Kubernetes NetworkPolicy.
2. Hardened runtime: non-root (UID 1000), read-only root filesystem, all
   Linux capabilities dropped, seccomp RuntimeDefault.
3. Multi-arch (amd64/arm64), cosign-signed with SBOM and SLSA provenance;
   Helm chart for Amazon EKS with probes, a PodDisruptionBudget, and
   optional Prometheus metrics.

## Categories

Infrastructure Software (AWS Marketplace has no "Database" category).

## Search keywords

PostgreSQL, Postgres, connection pooler, connection pooling, pgagroal,
database, Amazon RDS, Aurora, high availability, failover, Kubernetes, Helm,
EKS

## Delivery option

- **Delivery-option label (`DeliveryOptionTitle`): `Helm chart (Amazon EKS)`**
  — this is the correct label. If the live listing shows a placeholder or
  auto-generated delivery-option title, replace it with this.
- **Version title (`VersionTitle`): `1.4.5`** — Elevarq packaging version;
  this version bundles upstream pgagroal 2.1.0.
- Compatible services: EKS.
- Image: `709825985650.dkr.ecr.us-east-1.amazonaws.com/elevarq/elevarq-pgagroal:1.4.5`
- Chart: `709825985650.dkr.ecr.us-east-1.amazonaws.com/elevarq/elevarq-pgagroal-chart:1.4.5`

## Version

This listing's version is **Elevarq packaging v1.4.5**, which bundles
**upstream pgagroal 2.1.0**. The two numbers are independent and intentionally
different: **1.4.5** is the Elevarq packaging version (how the image is
built, hardened, and shipped); **2.1.0** is the upstream pooler release
inside it. State the relationship wherever both appear — e.g. "Elevarq
packaging v1.4.5, bundling upstream pgagroal 2.1.0" — so readers do not read
1.4.5 as a pgagroal version.

## Usage instructions

1. Authenticate Helm to the AWS Marketplace registry:

   ```sh
   aws ecr get-login-password --region us-east-1 \
     | helm registry login --username AWS --password-stdin \
         709825985650.dkr.ecr.us-east-1.amazonaws.com
   ```

2. Create a Kubernetes Secret with your existing PostgreSQL credentials. The
   image ships no default or hardcoded password — these are your own database
   credentials.

   ```sh
   kubectl create namespace pgagroal
   kubectl -n pgagroal create secret generic pgagroal-pg-credentials \
     --from-literal=PG_USERNAME=<app-user> \
     --from-literal=PG_PASSWORD=<app-password>
   ```

3. Create a values file. Save the following as `pgagroal-values.yaml`,
   pointing it at your backend and the Secret from step 2:

   ```yaml
   postgresql:
     host: <postgres-host>
     port: 5432
   credentials:
     existingSecret: pgagroal-pg-credentials
   # Optional: if your EKS pod network is outside the RFC1918 ranges
   # (e.g. a 100.64.0.0/10 secondary CIDR), set the HBA allowlist to it:
   # pgagroal:
   #   hbaSource: "100.64.0.0/10"
   ```

   The chart fails to install if no credential source is provided (no
   empty-password default).

4. Install into your cluster:

   ```sh
   helm install pgagroal \
     oci://709825985650.dkr.ecr.us-east-1.amazonaws.com/elevarq/elevarq-pgagroal-chart \
     --version 1.4.5 -n pgagroal --create-namespace -f pgagroal-values.yaml
   ```

5. Point applications at the `pgagroal` Service on port 6432. A NetworkPolicy
   is enabled by default and admits same-namespace clients; if your clients
   run in another namespace, set `networkPolicy.ingressNamespaceSelectors`.
   Full configuration: https://elevarq.com/docs/pgagroal-container

## Additional resources

- Documentation — https://elevarq.com/docs/pgagroal-container
- Security policy — https://github.com/Elevarq/pgAgroal/blob/main/SECURITY.md

## Support

Community support via GitHub Issues at https://github.com/Elevarq/pgAgroal.
Report security vulnerabilities to security@elevarq.com (see SECURITY.md).

## Notes for the portal operator

- The portal's `UsageInstructions` field collapses rich formatting. Paste the
  YAML block exactly, preserving its two-space indentation, so it stays valid
  copy-paste YAML.
- The catalog-API change-set carrying these values is
  [`catalog-api/02-add-helm-delivery.json`](catalog-api/02-add-helm-delivery.json)
  (VersionTitle 1.4.5; image and chart at the `:1.4.5` Marketplace ECR tags).
  Re-host the 1.4.5 image and chart into the Marketplace ECR before adding
  the delivery option (see [`catalog-api/README.md`](catalog-api/README.md)).
