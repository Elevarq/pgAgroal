# Specification: HBA Source-Address Restriction

## Status

ACTIVE (#48)

## Purpose

Restrict which **source addresses** the pgagroal pooler accepts at the
host-based-authentication (HBA) layer, so that a pooler accidentally
exposed on a public interface rejects public-internet sources instead of
accepting `host all all all all` (any database, any user, any address,
any method). This is defence in depth: the backend PostgreSQL remains the
authority for user authentication. The restriction is operator-configurable
and defaults to the RFC1918 private ranges, which cover the realistic
deployment networks (Docker bridge, Kubernetes pod networks, on-prem
private subnets) without breaking them.

## Interfaces

### Inputs

| Input | Type | Default | Constraints |
|-------|------|---------|-------------|
| `PGAGROAL_HBA_SOURCE` (env) / `pgagroal.hbaSource` (Helm) | string | RFC1918 ranges, octet-aligned (see note) | Comma-separated list of CIDRs, or the literal `all`. Whitespace around entries is ignored. |

> **pgagroal CIDR note**: pgagroal's HBA matches CIDRs on octet
> boundaries only — `/8`, `/16`, `/24` work; `/12` does **not**.
> RFC1918's `172.16.0.0/12` is therefore expressed as its sixteen `/16`
> blocks (`172.16.0.0/16` .. `172.31.0.0/16`). The full default is
> `10.0.0.0/8` + those sixteen `/16`s + `192.168.0.0/16` (18 entries).
| `PGAGROAL_ALLOW_UNKNOWN_USERS` (env) / `pgagroal.allowUnknownUsers` (Helm) | bool-string | `true` | `true` = transparent pooling (pass unknown users to the backend); `false` = only pgagroal-registered users. |

### Outputs

- `pgagroal_hba.conf` containing one `host all all <cidr> all` line per
  entry in `PGAGROAL_HBA_SOURCE`.
- `pgagroal.conf` with `allow_unknown_users` set from
  `PGAGROAL_ALLOW_UNKNOWN_USERS`.

## Behaviors

- **B1** — Given `PGAGROAL_HBA_SOURCE` unset, when the entrypoint generates
  the HBA file, then it contains one `host` line per default RFC1918 CIDR
  (18 lines: `10.0.0.0/8`, `172.16.0.0/16` .. `172.31.0.0/16`,
  `192.168.0.0/16`), and no line with address `all`. Every default CIDR
  uses an octet-aligned mask so pgagroal matches it.
- **B2** — Given `PGAGROAL_HBA_SOURCE` set to a single CIDR, when the HBA
  file is generated, then it contains exactly one `host` line for that CIDR.
- **B3** — Given `PGAGROAL_HBA_SOURCE` set to multiple comma-separated
  CIDRs (with arbitrary surrounding whitespace), when the HBA file is
  generated, then it contains one `host` line per CIDR, whitespace trimmed.
- **B4** — Given `PGAGROAL_HBA_SOURCE=all`, when the HBA file is generated,
  then it contains a single `host all all all all` line (explicit
  legacy opt-out).

## Rules

- **R1** — Each generated HBA line has the form
  `host    all       all   <address>   all`.
- **R2** — `allow_unknown_users` in the rendered `pgagroal.conf` equals the
  value of `PGAGROAL_ALLOW_UNKNOWN_USERS`.

## Invariants

- **I1** — The default rendered HBA never contains an `all` source address.
  Accepting any source is only possible by an explicit `PGAGROAL_HBA_SOURCE=all`.
- **I2** — Source restriction is defence in depth, not authentication: the
  backend PostgreSQL still authenticates every user. Changing
  `PGAGROAL_HBA_SOURCE` never bypasses backend auth.

## Failure conditions

| Trigger | Response |
|---------|----------|
| `PGAGROAL_HBA_SOURCE` contains an empty element (e.g. trailing comma) | The empty element is skipped; no malformed HBA line is emitted. |

## Constraints / NFR

- The image and the Helm chart MUST generate the HBA identically (the chart
  copies the same template and runs the same entrypoint). A `host: "*"`
  bind SHOULD be paired with a Kubernetes `NetworkPolicy` (see #49).
- The docker-compose example MUST NOT publish the pooler port on all host
  interfaces by default (loopback bind, or explicit opt-out).
