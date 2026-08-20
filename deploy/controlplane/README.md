# Publishing pgAgroal to the Control Plane Template Catalog

This directory holds the **Control Plane (cpln.io) Template Catalog** package for the
public/free pgAgroal container. It follows the reusable process proven on Elevarq
Signals. `pgagroal/` is a drop-in for `controlplane-com/templates/pgagroal/`.

## How the catalog works (verified)

- The catalog is a set of Helm charts in the public repo
  [`controlplane-com/templates`](https://github.com/controlplane-com/templates)
  that render Control Plane resources (not Kubernetes objects). On merge to `main`
  a workflow publishes each version to `oci://ghcr.io/controlplane-com/templates`.
- It is **internally curated** — every template is authored/merged by Control Plane
  staff; no external PR has ever landed. So publication is a **partner engagement**:
  hand them the template (they adopt/merge it), not a self-service PR.
- Templates deploy into an existing GVC (`createsGvc: false`); the platform injects
  the GVC name as `{{ .Values.global.cpln.gvc }}`.

## Layout

```
pgagroal/
├── icon.png                        # square, transparent (Elevarq mark)
├── LISTING.md                      # internal listing copy (not submitted)
├── tests/render-acceptance.sh      # internal acceptance suite (not submitted)
└── versions/1.0.0/
    ├── Chart.yaml                  # category: database, createsGvc:false, cpln-common dep
    ├── README.md                   # user-facing install + verify
    ├── values.yaml                 # documented inputs, digest-pinned image, no plaintext secrets
    └── templates/
        ├── _helpers.tpl            # naming + validation + image enforcement + tags
        ├── identity.yaml
        ├── policy.yaml             # reveal on the secret
        ├── secret-credentials.yaml # dictionary: backend password
        └── workload-pgagroal.yaml  # standard (stateless) pooler; port 6432; exec probe
```

Only `pgagroal/icon.png` + `versions/<semver>/…` is submitted — `LISTING.md`, `tests/`,
and this runbook are internal.

## pgAgroal-specific decisions

- **Stateless `standard` workload** (no volumeset) — the pooler keeps only an
  in-memory pool.
- **Client-facing TCP port 6432** exposed to the same GVC; **egress** scoped to the
  backend PostgreSQL TCP port (`outboundAllowPort`) with a broad CIDR (rotating
  managed DB IPs).
- **Health** via the `pgagroal-cli … ping` exec probe (the image's canonical check).
- **Auth:** clients authenticate to the pooler with the backend user's credentials
  (`auth.username`/`auth.password`); the password lives in a Control Plane dictionary
  secret revealed only to the pgAgroal identity. Unknown-user passthrough is off.
- **Known limitation:** TLS (client↔pooler and pooler↔backend) is not configurable in
  this container version — documented in the README; suitable for private-network
  backends.

## Validate locally (no account writes)

```bash
cd pgagroal/versions/1.0.0
helm dependency build
helm lint .                                          # metadata.name warns — expected (cpln resources)
helm template validation . --set global.cpln.gvc=validation-gvc
bash ../../tests/render-acceptance.sh                # positive + negative cases
```

## Publish (external gate)

Hand the `pgagroal/` package to your Control Plane contact (partner engagement). If
they prefer a PR, open one against `controlplane-com/templates` adding `pgagroal/`
and @-mention a maintainer. The full generic runbook (checklist, category vocabulary,
outreach) lives in the Signals repo's `deploy/controlplane/` kit.
