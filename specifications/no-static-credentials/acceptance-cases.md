# Acceptance Cases: No Static Credentials in the Tracked Tree

Derived from `spec.md`. Each case maps to behaviors, rules, or
invariants in the specification. Minimum set: one normal, one boundary,
one invalid, one failure.

## AC-01: Tracked tree is free of credential literals (normal)

**Spec refs**: B1, R1, R4, I1

**Given**: the tracked tree at the current commit
**When**: `test/validation/no-static-credentials-test.sh` runs its scan
**Then**:
- No tracked file matches a banned credential literal
- No init script creates a role with a literal password
- The test exits zero

## AC-02: Chart renders by-reference only (normal)

**Spec refs**: B2, B3, R2, I2

**Given**: the Helm chart with default values, and again with
`pgexporter.enabled=true`
**When**: `helm template` renders each configuration
**Then**:
- Rendering succeeds in both configurations
- The output contains no `kind: Secret` and no credential value
- Workload env vars reference operator-provided Secret names only

## AC-03: Placeholders remain allowed (boundary)

**Spec refs**: R6

**Given**: documentation containing `<password>`-style placeholders and
`CHANGEME` markers on non-secret fields (hostnames, image repositories)
**When**: the scan runs
**Then**: these are not findings; the test exits zero

## AC-04: Introduced credential literal is caught (invalid)

**Spec refs**: B1, R1, I3

**Given**: a tracked file into which a banned credential literal is
introduced (simulated in a temporary copy of the scan input)
**When**: the scan runs against that input
**Then**: the test exits non-zero and names the offending file

## AC-05: Missing runtime credential fails fast, not silently (failure)

**Spec refs**: R3

**Given**: a shell without the required credential variables
**When**: `docker compose config` resolves the stack configuration
**Then**: the command exits non-zero naming the missing variable
(delegated to `compose-pgexporter-integration` AC-07; asserted there)
