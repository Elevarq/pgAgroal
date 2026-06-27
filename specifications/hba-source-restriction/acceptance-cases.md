# Acceptance Cases: HBA Source-Address Restriction

Derived from `spec.md`. Each case maps to behaviors, rules, or invariants.
Verified by `test/validation/hba-source-test.sh` (dockerless: sources the
entrypoint and exercises `build_hba_lines` + envsubst rendering).

## AC-01: Default restricts to RFC1918 (octet-aligned), never `all`

**Spec refs**: B1, I1, I3, R1

**Given**: `PGAGROAL_HBA_SOURCE` unset
**When**: the HBA file is generated
**Then**:
- 18 `host` lines are emitted: `10.0.0.0/8`, the sixteen `172.16.0.0/16`
  .. `172.31.0.0/16`, and `192.168.0.0/16`
- No line has address `all`
- No line uses the non-octet `/12` mask (pgagroal cannot match it)
- Every line matches `host    all       all   <cidr>   scram-sha-256`
- Every line's auth method is `scram-sha-256` (never `trust`/`all`)

## AC-02: Single custom CIDR

**Spec refs**: B2

**Given**: `PGAGROAL_HBA_SOURCE=10.244.0.0/16`
**When**: the HBA file is generated
**Then**: exactly one `host` line, for `10.244.0.0/16`

## AC-03: Multiple CIDRs with whitespace

**Spec refs**: B3

**Given**: `PGAGROAL_HBA_SOURCE=" 10.0.0.0/8 , 192.168.0.0/16 "`
**When**: the HBA file is generated
**Then**: two `host` lines, for `10.0.0.0/8` and `192.168.0.0/16`, with the
surrounding whitespace trimmed

## AC-04: Explicit `all` opt-out keeps the `scram-sha-256` method

**Spec refs**: B4, I3

**Given**: `PGAGROAL_HBA_SOURCE=all`
**When**: the HBA file is generated
**Then**: a single `host    all       all   all   scram-sha-256` line (the
address is the any-source opt-out; the method is still `scram-sha-256`)

## AC-05: Empty element skipped

**Spec refs**: FC (trailing comma)

**Given**: `PGAGROAL_HBA_SOURCE="10.0.0.0/8,"`
**When**: the HBA file is generated
**Then**: exactly one `host` line, for `10.0.0.0/8` (no malformed line for
the empty element)

## AC-06: allow_unknown_users from env

**Spec refs**: R2

**Given**: `PGAGROAL_ALLOW_UNKNOWN_USERS=false`
**When**: `pgagroal.conf` is rendered from the template
**Then**: the rendered config contains `allow_unknown_users = false`

## AC-07: allow_unknown_users hardened default is false

**Spec refs**: B5, R2

**Given**: `PGAGROAL_ALLOW_UNKNOWN_USERS` unset
**When**: the entrypoint renders `pgagroal.conf` (applying its default)
**Then**: the rendered config contains `allow_unknown_users = false`
