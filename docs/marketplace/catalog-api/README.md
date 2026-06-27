# AWS Marketplace Catalog API change-sets (Elevarq pgAgroal container product)

Change-sets to drive the AWS Marketplace container listing for **Elevarq
pgAgroal** via the **Catalog API** (`StartChangeSet`). Tracks
[Elevarq/pgAgroal#55](https://github.com/Elevarq/pgAgroal/issues/55); schemas
are from the official
[container-products Catalog API reference](https://docs.aws.amazon.com/marketplace-catalog/latest/api-reference/container-products.html).

> **v1.4.0 (harden-then-resubmit).** The public version is now **Elevarq
> packaging v1.4.0** (bundling upstream pgagroal 2.1.0), superseding the
> in-review 1.3.0. `02-add-helm-delivery.json` here is set to 1.4.0; re-host
> the **1.4.0** image + chart into the Marketplace ECR (same steps as the
> 1.3.0 re-host below, with `:1.4.0` tags) before adding the delivery option.
> Do not broaden 1.3.0 to Public.

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
| Product info (title, descriptions, highlights, categories, keywords, logo) | **API** — `UpdateInformation` (`03-update-information.json`); works on a Draft | done |
| Release Draft → Limited | **API** — `ReleaseProduct` (empty DetailsDocument) | pending |
| Add the Helm delivery version | **API** — `02-add-helm-delivery.json` (`AddDeliveryOptions`) — only once Limited | pending (after ReleaseProduct) |
| Free offer (legal/EULA/support terms) | **API** — `Offer@1.0`: `CreateOffer` + `ReleaseOffer` | pending (gated on EULA legal sign-off) |
| Publish **Limited → Public** | **API** — `UpdateVisibility` `TargetVisibility: Public` (triggers AWS manual review) | pending (gated on EULA + explicit go) |

## The first publish IS fully Catalog-API-doable (verified)

Earlier this doc said the first publish was portal-only — **that was wrong**.
Verified against current AWS docs and by running the calls, the whole sequence
is API-driven (no AMMP web UI):

1. `UpdateInformation` — populate all product metadata. **Works on a Draft**
   and requires **all** core fields in one call: `ProductTitle`,
   `ShortDescription`, `LongDescription`, `LogoUrl`, `Highlights` (max 3),
   `AdditionalResources`, `SupportDescription`, `Categories` (1-3),
   `SearchKeywords` (max 15, ≤250 combined chars). Done — see
   `03-update-information.json`.
2. `ReleaseProduct` (empty `DetailsDocument`) — moves Draft → **Limited**. This
   is the step that unblocks `AddDeliveryOptions`.
3. `AddDeliveryOptions` (`02-add-helm-delivery.json`) — adds the Helm version.
   On a **Draft** it fails `INCOMPATIBLE_PRODUCT_STATUS` ("Use a Public or
   Limited or Restricted product"); it needs the product Limited/Public first
   (hence step 2).
4. `Offer@1.0` (`CreateOffer` + `ReleaseOffer`) — a transactable product needs
   an offer even when free; the EULA / legal / support terms attach here, so
   this step is gated on legal sign-off.
5. `UpdateVisibility` `TargetVisibility: Public` — the public launch. API call,
   but AWS Seller Operations runs a manual review. Do not run without the EULA
   signed and explicit go.

### LogoUrl must be an S3 URL

`UpdateInformation`'s `LogoUrl` field regex accepts any https URL, but a deeper
`INVALID_MEDIA` check rejects non-S3 hosts: a live logo on `https://elevarq.com/...`
failed with *"Provide a new URL for media stored in S3."* The logo therefore
lives in S3. We host it in a scoped public-read bucket
(`elevarq-marketplace-public`, `GetObject` on the `logos/` prefix only) at
`https://elevarq-marketplace-public.s3.amazonaws.com/logos/elevarq-512.png`
(512×512 transparent PNG rendered from the website `app/icon.svg` mark; the
Elevarq company logo, reused across the portfolio).

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

## Apply a change-set

```sh
aws marketplace-catalog start-change-set \
  --catalog AWSMarketplace \
  --cli-input-json file://docs/marketplace/catalog-api/03-update-information.json
# then poll: aws marketplace-catalog describe-change-set --catalog AWSMarketplace --change-set-id <id>
```

`03-update-information.json` (product info) is done. `02-add-helm-delivery.json`
must run **after** `ReleaseProduct` (it needs the product Limited; on a Draft it
fails `INCOMPATIBLE_PRODUCT_STATUS`), and it triggers AWS's async ingestion scan
of the image + chart. The offer (and thus the path to Public) is gated on the
EULA / entity wording sign-off.

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
