# AWS Marketplace Catalog API change-sets (pgAgroal container product)

Change-sets to drive the AWS Marketplace container listing for **Elevarq
pgAgroal** via the **Catalog API** (`StartChangeSet`). Tracks
[Elevarq/pgAgroal#55](https://github.com/Elevarq/pgAgroal/issues/55); schemas
are from the official
[container-products Catalog API reference](https://docs.aws.amazon.com/marketplace-catalog/latest/api-reference/container-products.html).

The product already exists (Draft) and the ECR repos are already created:

| Item | Value |
|------|-------|
| Product entity | `prod-jl5oxsgdp4rla` ("Elevarq pgAgroal") |
| Product code | `5xbw2q7ywbjgtszgclgwlj13v` |
| Image repo | `709825985650.dkr.ecr.us-east-1.amazonaws.com/elevarq/elevarq-pgagroal` |
| Chart repo | `709825985650.dkr.ecr.us-east-1.amazonaws.com/elevarq/elevarq-pgagroal-chart` |

Unlike a fresh listing, **`02-add-helm-delivery.json` here is concrete** (real
URIs filled in) — not a `${PLACEHOLDER}` template — because the product and
repos are known.

## What is API-driven vs portal-only

| Step | How | State |
|------|-----|-------|
| Create product (Draft) + ECR repos | **API** — `CreateProduct` + `AddRepositories` | done |
| Push image + Helm chart into the ECR repos | **CLI** — see "Re-host" below | done (1.3.0) |
| First listing: product info + first Helm delivery option + EULA → submit | **Portal** (AMMP) — required; the API cannot stage the first version on a Draft (see below) | pending |
| Subsequent Helm delivery versions | **API** — `02-add-helm-delivery.json` (`AddDeliveryOptions` / `HelmDeliveryOptionDetails`) — only once the product is Limited/Public | for later version bumps |
| Publish **Limited → Public** | **Portal** (AMMP) submit + limited-listing-URL approval | pending |

## `AddDeliveryOptions` requires a non-Draft product (verified)

Running `02-add-helm-delivery.json` against the Draft product fails fast:

```
INCOMPATIBLE_PRODUCT_STATUS — "Use a Public or Limited or Restricted product."
```

`AddDeliveryOptions` is a **version-update** change type: it adds a new version
to a product that is **already Limited/Public**. It cannot perform the initial
Draft → Limited publish. So the **first** listing — product description,
categories, support, the first Helm delivery option (referencing the ECR
image + chart we re-hosted), and the EULA — is assembled and submitted in the
**AMMP portal**, which moves the product to Limited. The values in
`02-add-helm-delivery.json` and `../aws-listing.md` map directly onto the
portal's Helm-delivery and product-info forms. Keep the change-set for the
**next** version bump (e.g. 1.3.1 / 1.4.0), when the product is Limited/Public
and the API path works.

## Re-host (done for 1.3.0)

The 1.3.0 image + chart are already in the Marketplace ECR. The commands used
(skopeo is **not** required — `docker buildx imagetools create` copies the
multi-arch manifest registry-to-registry):

```sh
MP=709825985650.dkr.ecr.us-east-1.amazonaws.com
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin "$MP"
aws ecr get-login-password --region us-east-1 \
  | helm registry login --username AWS --password-stdin "$MP"

# Image: multi-arch copy ghcr -> Marketplace ECR
docker buildx imagetools create \
  -t "$MP/elevarq/elevarq-pgagroal:1.3.0" ghcr.io/elevarq/pgagroal:1.3.0

# Chart: pull, repoint default image to the MP ECR repo, rename so it lands at
# the granted repo path, repackage, push (see "Chart path gotcha" below).
```

## Apply the Helm delivery option

```sh
aws marketplace-catalog start-change-set \
  --catalog AWSMarketplace \
  --cli-input-json file://docs/marketplace/catalog-api/02-add-helm-delivery.json
# then poll: aws marketplace-catalog describe-change-set --catalog AWSMarketplace --change-set-id <id>
```

This triggers AWS's async ingestion scan of the image + chart. Do **not** run it
until the EULA / entity wording is signed off (it is a draft-stage change, but
we sequence it with the rest of the submit).

## Constraints baked into the change-set (from the API error catalog)

- `RepositoryType` must be `"ECR"` (only allowed value).
- Helm `HelmChartUri` tag must be **SemVer 2** — `1.3.0` qualifies.
- No `latest` image tag (`INVALID_CONTAINER_IMAGE_TAG`).
- All Helm chart images must live in repos created via `AddRepositories`
  (`INVALID_HELM_CHART_IMAGES`). The published chart's default
  `image.repository` is repointed from `ghcr.io/elevarq/pgagroal` to the
  Marketplace ECR image repo before the chart is pushed; `helm template`
  asserts no `ghcr.io` image remains.
- Repository names are **flat** (`elevarq/elevarq-pgagroal`,
  `elevarq/elevarq-pgagroal-chart`).
- `SCAN_ERROR` blocks the version if image scanning finds vulnerabilities — the
  1.3.0 image is Trivy-clean (HIGH/CRITICAL, `--ignore-unfixed`) after the
  libssl3 `deb12u2` base bump.
- `CompatibleServices: ["EKS"]` only. Adding `EKS-Anywhere` requires a
  license-secret `OverrideParameters` entry — out of scope for the free EKS
  listing.

## Chart path gotcha (ECR repos are not hierarchical)

`helm push chart.tgz oci://$MP/elevarq/elevarq-pgagroal-chart` appends the chart
name and tries to create `elevarq/elevarq-pgagroal-chart/pgagroal` — a
**separate** ECR repository that does not exist and the seller cannot
auto-create cross-account → `403 Forbidden`. Fix: land the chart **exactly** at
the granted repo by renaming the chart so its name is the repo's last path
segment (`Chart.yaml name: elevarq-pgagroal-chart`) and pushing to the parent
(`oci://$MP/elevarq`). Buyer-facing resource names are preserved with
`nameOverride: "pgagroal"` in values. Final chart URI:
`$MP/elevarq/elevarq-pgagroal-chart:1.3.0`.

## SignatureVerificationKey — not an image-signing gate

The product entity carries an active RSA public key (`PublicKeyVersion 1`). This
is the **metering** signature-verification key for the `RegisterUsage` flow
(AWS generates the keypair, holds the private half, stamps the public half into
the product). It is **not** an image-signing requirement: there is no signing
field or signing-related error in the container-product API, image signing is
not required to `AddDeliveryOptions` or publish, and free ECS/EKS products are
exempt from `RegisterUsage`. No action needed on the key.
