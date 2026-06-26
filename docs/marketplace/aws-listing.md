# AWS Marketplace listing — Elevarq pgAgroal (free container product)

Working package for listing **Elevarq pgAgroal** on AWS Marketplace as a
**free container product** (Helm chart delivery). Tracks
[Elevarq/pgAgroal#55](https://github.com/Elevarq/pgAgroal/issues/55).

This file is the content + steps we drive via the AWS Marketplace Catalog API
(or paste into the AWS Marketplace Management Portal / AMMP).

> **Status:** draft. One gate remains before submit: legal sign-off on the
> EULA / entity wording (§4). The `SignatureVerificationKey` question is
> resolved (§6 — it is the inert metering key, not an image-signing
> requirement). Do **not** run the submit / visibility change-sets until legal
> clears.

## 0. Pre-publish gate

- [x] Seller account is a registered seller (free publishing needs no
      tax/bank; independent of the paid Analyzer review).
- [x] **v1.3.0** tagged and published (non-prerelease) — image + cosign-signed
      OCI Helm chart on ghcr, GitHub Release live.
- [x] Marketplace ECR repos created (`AddRepositories`): `elevarq/elevarq-pgagroal`
      (image) and `elevarq/elevarq-pgagroal-chart` (chart).
- [x] 1.3.0 image + chart re-hosted into the Marketplace ECR (see
      `../../README` and the re-host notes; chart repoints its default image to
      the Marketplace ECR repo, no `ghcr.io`).

## 1. Product metadata

| Field | Value |
|-------|-------|
| Product title | Elevarq pgAgroal |
| Product code | `5xbw2q7ywbjgtszgclgwlj13v` |
| Entity ID | `prod-jl5oxsgdp4rla` |
| Short description | Production-hardened pgagroal connection pooler for PostgreSQL — non-root, signed, multi-arch container with a Helm chart. No telemetry. |
| Long description | Elevarq pgAgroal is an open-source (BSD-3-Clause) production container packaging of [pgagroal](https://github.com/pgagroal/pgagroal), a high-performance connection pooler for PostgreSQL. pgagroal 2.1.0 is built from pinned upstream source on Debian and shipped as a hardened runtime: **non-root** (UID 1000), **all Linux capabilities dropped**, **read-only root filesystem**, and **seccomp RuntimeDefault**. Images are **multi-arch** (linux/amd64 + linux/arm64), **cosign-signed** (keyless, GitHub OIDC) with **SBOM and SLSA provenance** attached. The Helm chart ships liveness/readiness probes, a PodDisruptionBudget, an optional Prometheus metrics port, and least-privilege security contexts. There is **no telemetry and no data egress to Elevarq**. |
| Categories _(confirm against AMMP list)_ | Database / Infrastructure Software |
| Search keywords | PostgreSQL, Postgres, connection pooler, connection pooling, pgagroal, database, Amazon RDS, Aurora, high availability, failover, Kubernetes, Helm, EKS |
| Vendor | Elevarq (DBA of Scantr LLC) |
| Pricing | Free |
| Source / homepage | https://github.com/Elevarq/pgAgroal |
| License | BSD-3-Clause |

> **Keyword note — "pgbouncer".** Listing a competitor/other-project name
> (e.g. `pgbouncer`) as a bare search keyword is a policy risk: AWS Marketplace
> container-product policies prohibit metadata that is misleading or references
> third-party names/trademarks you don't own, and reviewers can reject the
> listing for it. Recommended instead: compete on the **factual feature
> story** in the long description (built-in health check, failover, Prometheus
> console, vault encryption, hardened non-root runtime) rather than capturing a
> competitor's search traffic by name. Decision deferred to the listing owner /
> counsel before submit; the keyword list above intentionally omits it.

## 2. Delivery option — Helm chart (primary)

- **Method:** Helm chart, installed via the Helm CLI (Amazon EKS, or
  self-managed EKS Anywhere / EC2 / on-prem).
- **Chart + image:** re-hosted into the AWS-Marketplace-owned ECR repos. The
  published chart's default image points at the Marketplace ECR image repo —
  **not** `ghcr.io` (AWS rejects external chart images:
  `INVALID_HELM_CHART_IMAGES`).
- Catalog-API change-set: [`catalog-api/02-add-helm-delivery.json`](catalog-api/02-add-helm-delivery.json)
  (concrete URIs, `ReleaseName`/`Namespace` = `pgagroal`).

### Buyer usage instructions (rendered on the listing)

```sh
# Authenticate Helm to the AWS Marketplace registry (buyer side)
aws ecr get-login-password --region <region> \
  | helm registry login --username AWS --password-stdin \
      709825985650.dkr.ecr.us-east-1.amazonaws.com
```

Configure a values file, then install with `-f`:

```yaml
# pgagroal-values.yaml
postgresql:
  host: <postgres-host>
  port: 5432
credentials:
  username: <app-user>
  password: <app-password>   # or set credentials.existingSecret
```

```sh
helm install pgagroal \
  oci://709825985650.dkr.ecr.us-east-1.amazonaws.com/elevarq/elevarq-pgagroal-chart \
  --version 1.3.0 -n pgagroal --create-namespace -f pgagroal-values.yaml
```

Applications then connect through the `pgagroal` Service on port `6432`. Full
configuration and operations are documented in the
[project README](https://github.com/Elevarq/pgAgroal) and
[`install-from-aws-marketplace.md`](install-from-aws-marketplace.md).

## 3. Support & maintenance (free-product eligibility)

- **Support process:** GitHub Issues at https://github.com/Elevarq/pgAgroal;
  security reports via `SECURITY.md` (`security@elevarq.com`).
- **Update cadence:** versioned releases via CI (`publish.yml`) with
  cosign-signed, SBOM + SLSA-provenance, Trivy-scanned multi-arch images and a
  signed OCI Helm chart; Debian base security updates applied; security patches
  cut as needed.

## 4. License terms

- Customer-facing EULA (upload-ready): [`EULA.md`](EULA.md) — a clean custom
  EULA referencing the BSD-3-Clause license. This is the artifact submitted to
  AWS Marketplace; it contains contract text only.
- Decision rationale + counsel gates: [`EULA-review-notes.md`](EULA-review-notes.md)
  — custom-EULA-vs-SCMP decision, the Scantr LLC dba Elevarq entity gate, and
  the seller-entity / EULA-party / `LICENSE`-copyright alignment. **Legal
  sign-off required** before submission.

## 5. Submit checklist (ordered)

1. [x] Confirm registered-seller status (§0).
2. [x] Publish `v1.3.0`.
3. [x] Create Marketplace ECR repos (`AddRepositories`).
4. [x] Re-host the 1.3.0 image + Helm chart into the Marketplace ECR repos.
5. [x] Resolve the `SignatureVerificationKey` requirement (§6) — not an
       image-signing gate; no action needed.
6. [ ] **First publish is portal-driven.** In AMMP, fill product info / §1
       copy + add the first **Helm delivery option** (referencing the ECR
       image + chart from step 4; field values in
       [`catalog-api/02-add-helm-delivery.json`](catalog-api/02-add-helm-delivery.json))
       + attach the EULA. The Catalog API `AddDeliveryOptions` change type
       **cannot** stage the first version on a Draft product
       (`INCOMPATIBLE_PRODUCT_STATUS`) — it is for version updates once the
       product is Limited/Public.
7. [ ] Legal sign-off on the EULA / entity wording (§4).
8. [ ] Submit → AWS review (scans the image + chart).
9. [ ] Preview + approve the **limited listing URL** (product is now Limited).
10. [ ] Request **Limited → Public** → live.
11. [ ] _Future version bumps:_ `AddDeliveryOptions` via the Catalog API now works.

## 6. Decisions & open questions

**Open (must clear before submit)**

- **EULA / entity wording** — counsel review (Scantr LLC dba Elevarq).
- **Categories** — confirm exact values against the AMMP category list.

**Decided**

- **`SignatureVerificationKey` is NOT an image-signing gate.** The active RSA
  public key (PublicKeyVersion 1) on the product is the **metering**
  signature-verification key for the `RegisterUsage` flow: AWS auto-generates
  the keypair at product creation and holds the private half; the seller never
  signs anything with it, and it sits inert unless a buyer's container chooses
  to verify a `RegisterUsage` response. Image signing is **not required** to
  `AddDeliveryOptions` or publish — there is no signing field or signing-related
  error in the container-product API. Free ECS/EKS products are exempt from
  `RegisterUsage` entirely. The real ingestion gate is AWS's vulnerability /
  secret **scan** (`SCAN_ERROR`), which our Trivy-clean image passes. No action
  needed on the key. Refs: AWS Marketplace Catalog API (container products),
  container product policies, and billing-integration (`RegisterUsage`) docs.

- **Cosign GHCR signatures do not carry into the Marketplace ECR.** The
  multi-arch copy moves only the image; AWS re-scans (and may re-sign) on
  ingestion. Re-signing the Marketplace ECR artifacts is a possible later
  enhancement.
- **Chart path.** The chart is published at the granted ECR repo
  `elevarq/elevarq-pgagroal-chart` (chart renamed to match the repo's last
  path segment; buyer-facing resource names preserved via `nameOverride:
  pgagroal`).
