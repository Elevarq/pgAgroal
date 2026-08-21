# Specification: HBA Source-Address Restriction

## Status

ACTIVE (#48; hardened for v1.4.0 — auth method `scram-sha-256`,
`allow_unknown_users` default `false`)

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
| `PGAGROAL_ALLOW_UNKNOWN_USERS` (env) / `pgagroal.allowUnknownUsers` (Helm) | bool-string | `false` | `true` = transparent pooling (pass unknown users to the backend); `false` (hardened default) = only pgagroal-registered users. |

### Outputs

- `pgagroal_hba.conf` containing one `host all all <cidr> scram-sha-256`
  line per entry in `PGAGROAL_HBA_SOURCE`. The authentication method is
  always `scram-sha-256` (never `trust`/`all`).
- `pgagroal.conf` with `allow_unknown_users` set from
  `PGAGROAL_ALLOW_UNKNOWN_USERS` (default `false`).

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
  then it contains a single `host all all all scram-sha-256` line (the
  address is the legacy any-source opt-out; the method stays
  `scram-sha-256`).
- **B5** — Given `PGAGROAL_ALLOW_UNKNOWN_USERS` unset, when `pgagroal.conf`
  is rendered, then `allow_unknown_users = false` (the hardened default —
  unknown users are not passed through to the backend).
- **B6** — Given `PGAGROAL_HBA_SOURCE` containing an entry that is neither `all`
  nor a CIDR (e.g. `all trust #`, or any value with whitespace, `#`, or a bare
  auth method), when the HBA file is generated, then that entry is dropped with a
  warning and no HBA line is emitted for it — so an attacker-controlled value
  cannot inject a `trust`/`all` method or comment out `scram-sha-256`.

## Rules

- **R1** — Each generated HBA line has the form
  `host    all       all   <address>   scram-sha-256`. The method field is
  always `scram-sha-256`.
- **R2** — `allow_unknown_users` in the rendered `pgagroal.conf` equals the
  value of `PGAGROAL_ALLOW_UNKNOWN_USERS`, which defaults to `false`.
- **R3** — Each `PGAGROAL_HBA_SOURCE` entry (after trimming) is accepted only if
  it matches `^(all|d.d.d.d/mask)$`; any other entry is dropped with a warning and
  produces no HBA line. This makes R1's `scram-sha-256`-only guarantee hold for
  every possible input.

## Invariants

- **I1** — The default rendered HBA never contains an `all` source address.
  Accepting any source is only possible by an explicit `PGAGROAL_HBA_SOURCE=all`.
- **I2** — Source restriction is defence in depth, not authentication: the
  backend PostgreSQL still authenticates every user. Changing
  `PGAGROAL_HBA_SOURCE` never bypasses backend auth.
- **I3** — Every generated HBA line uses auth method `scram-sha-256`; no
  generated line uses `trust` or `all` as its method, for any value of
  `PGAGROAL_HBA_SOURCE`.

## Failure conditions

| Trigger | Response |
|---------|----------|
| `PGAGROAL_HBA_SOURCE` contains an empty element (e.g. trailing comma) | The empty element is skipped; no malformed HBA line is emitted. |
| `PGAGROAL_HBA_SOURCE` contains an entry that is not `all` or a CIDR (injection attempt, stray token) | The entry is dropped with a warning to stderr; no HBA line is emitted for it (R3). |

## Constraints / NFR

- The image and the Helm chart MUST generate the HBA identically (the chart
  copies the same template and runs the same entrypoint). The `host: "*"`
  bind is backed by the chart's `NetworkPolicy`, which is enabled by default
  (see `specifications/network-and-bind-hardening/` and #49).
- The docker-compose example MUST NOT publish the pooler port on all host
  interfaces by default (loopback bind, or explicit opt-out).
