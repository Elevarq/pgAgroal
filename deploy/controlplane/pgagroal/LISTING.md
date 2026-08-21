# pgAgroal — Control Plane Catalog listing copy

Internal source of truth for the catalog-facing text (the upstream catalog has no
LISTING.md convention; keep in sync with the live listing if they use one).

- **Product name:** Elevarq pgAgroal
- **Category:** database
- **Publisher / vendor:** Elevarq (Scantr LLC d/b/a Elevarq)
- **Price:** Free (open source, BSD-3-Clause)
- **One-line description:** High-performance PostgreSQL connection pooler that fronts
  your existing database — connect clients to the pooler, not PostgreSQL directly.

## Fuller description

Elevarq pgAgroal is a hardened container packaging of the upstream pgagroal
connection pooler. It sits in front of an existing PostgreSQL database you already
run and multiplexes many client connections onto a small pool of backend
connections, cutting connection-setup overhead and protecting the database from
connection storms. Other workloads in your GVC connect to pgAgroal on port 6432
exactly as they would to PostgreSQL; pgAgroal handles the pooling transparently.

It is stateless (no volume), runs as a non-root user under restricted container
capabilities, and scales horizontally as independent replicas. Egress is restricted
to the backend's port, and only the configured pooled user is accepted.

## Main capabilities

- High-performance connection pooling using the PostgreSQL v3 wire protocol.
- Stateless and horizontally scalable (independent replicas).
- Hardened: non-root, dropped capabilities, egress scoped to the backend port,
  pre-registered user only (unknown-user passthrough disabled).
- Optional pgAgroal Prometheus metrics.
- Nothing bundled — you bring your own PostgreSQL.

## Requirements

- An existing PostgreSQL reachable from the GVC.
- A PostgreSQL role clients pool through (`CONNECT` plus the application-required
  schema and object privileges).
- Note: TLS to/from the pooler is not configurable in this version — use on a
  trusted private network path to the backend.

## Security & privacy

- Non-root (UID/GID 1000) under Control Plane's restricted container capabilities.
- Backend password held in a Control Plane secret, revealed only to the pgAgroal
  identity — never baked into the image.
- Egress restricted to the backend TCP port; only the pre-registered user accepted.

## PostgreSQL compatibility

Use a PostgreSQL major version still supported by the PostgreSQL project. This
container bundles upstream pgagroal 2.1.0; repository CI currently exercises
PostgreSQL 17. Managed services (Amazon RDS/Aurora, Azure Database for PostgreSQL,
Google Cloud SQL) require private network reachability to the backend **and** must
permit non-TLS client connections, because this container version cannot enable
backend TLS.

## Links

- Source & documentation: https://github.com/Elevarq/pgAgroal
- Upstream pgagroal: https://github.com/pgagroal/pgagroal
- Website: https://elevarq.com

## Positioning guardrails

This is the **free, open-source** pgAgroal container — not the Elevarq pgAgroal
Enterprise product. Present it as a lightweight PostgreSQL connection pooler; do
not imply Enterprise features (advanced auth, TLS termination, operator) are
included.
