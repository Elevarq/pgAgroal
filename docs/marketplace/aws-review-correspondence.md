# AWS Marketplace review correspondence — Elevarq pgAgroal

Audit record of the AWS Marketplace product-policy review for the public
listing of **Elevarq pgAgroal** (product `prod-jl5oxsgdp4rla`). Tracks
[#55](https://github.com/Elevarq/pgAgroal/issues/55) and
[#79](https://github.com/Elevarq/pgAgroal/issues/79).

## Round 1 — finding (2026-06-29)

AWS rejected the v1.4.0 `UpdateVisibility: Public` submission:

> **Static/default passwords:** Remove all hardcoded or default passwords.
> Use random password generation per instance or instance-id as initial
> password. Force password change on first login.
> (https://docs.aws.amazon.com/marketplace/latest/userguide/container-product-policies.html)

### Analysis

The image and chart ship **no** hardcoded/default password: no baked
user/admin/superuser files in the image, Trivy secret-scan clean, the
internal master key is generated randomly per container, and backend
credentials come from an operator-supplied Secret. What AWS's default
`helm template` produced was a **Secret with an empty `PG_PASSWORD`** (the
chart created a Secret from empty default values) — read as a "default
password". The policy's "random per instance / force change on first login"
language targets products that provision a login; pgAgroal provisions none
and authenticates to the customer's existing PostgreSQL.

### Fix (v1.4.1 → v1.4.2)

- **v1.4.1** made the chart fail-closed (refuse to render without a credential
  source). This **broke AWS ingestion**: AWS runs `helm template` with default
  values, which then failed (`INVALID_HELM_TEMPLATE`).
- **v1.4.2** (shipped) defaults `credentials.existingSecret: pgagroal-pg-credentials`
  with `create: false`. The default render emits only a `secretKeyRef`,
  creates no Secret, and contains **no credential value of any kind** — the
  same "no default/static password" guarantee, but it templates cleanly. The
  operator creates the named Secret with their existing credentials before
  installing.

### Resubmission (2026-06-30)

- v1.4.2 image + chart re-hosted to the Marketplace ECR.
- `AddDeliveryOptions` 1.4.2 → **SUCCEEDED** (passed `helm template` + scan).
- `UpdateVisibility: Public` resubmitted (change-set `17ndkceirrglw8vr6a50nim02`)
  → in AWS Seller-Ops review.

### Reply posted to the AWS case

> Thank you for the review. Elevarq pgAgroal is a PostgreSQL connection
> pooler; it provisions no user account and ships no hardcoded or default
> password.
>
> - The container image contains no credentials — no baked user/admin/superuser
>   files; the only config is connection templates (consistent with your secret
>   scan passing).
> - At runtime it authenticates to the customer's own existing PostgreSQL using
>   credentials the customer supplies. As of version 1.4.2, the Helm chart's
>   default values reference an external Kubernetes Secret the customer creates
>   with those credentials. A default `helm template` / `helm install` therefore
>   renders only a `secretKeyRef` and creates no Secret — the rendered manifests
>   contain no credential value of any kind. The chart never ships a blank,
>   default, or static password.
> - The only key material the container generates is an internal master key
>   (encrypting the pooler's local user file), generated randomly per container
>   instance from the kernel CSPRNG.
>
> Because the product creates no login of its own, "random password per
> instance" and "force change on first login" do not apply — there is no
> account for us to generate or rotate; the customer's PostgreSQL remains the
> sole authentication authority. Please let us know if any further change is
> needed.
