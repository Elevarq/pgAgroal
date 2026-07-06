# Specification: No Static Credentials in the Tracked Tree

Status: ACTIVE

> Issue: Elevarq/pgAgroal#89.
> Confirmed 2026-07-06.
> Origin: AWS Marketplace Seller-Ops rejected the listing twice with a
> "static/default passwords" finding. The published artifacts (image,
> chart, usage instructions) were credentials-by-reference and clean;
> the static credentials lived in this public repository (compose
> example, role init script, chart pgexporter values, tests, CI).

## Purpose

Guarantee that no tracked file in this repository carries a literal
credential value, and that every path by which a credential enters the
system is by-reference (a Kubernetes Secret the operator provides) or
runtime-injected (host-environment interpolation, ephemeral generated
test values). This is both a security property in its own right and a
hard requirement for AWS Marketplace listing approval, since the
repository is public and linked from the listing.

## Scope

Governs every tracked file: compose files, init scripts, Helm chart
values and templates, test scripts, CI workflows, Makefile, helper
scripts, and documentation examples.

Does NOT govern:
- Placeholders that cannot be mistaken for working values
  (`<password>`, `<app-password>`, `CHANGEME` markers on non-secret
  fields such as hostnames).
- Untracked local files (`.env`, which is gitignored).

## Interfaces

| Input | Type | Constraints |
|---|---|---|
| Compose credentials | env vars (`POSTGRES_PASSWORD`, `PGEXPORTER_PASSWORD`) | Interpolated fail-fast (`${VAR:?}`); documented in `.env.example` without values |
| Chart credentials (pooler) | Kubernetes Secret reference (`credentials.existingSecret`) | Keys `PG_USERNAME`, `PG_PASSWORD`; chart never creates the Secret |
| Chart credentials (pgexporter) | Kubernetes Secret reference (`pgexporter.credentials.existingSecret`) | Keys `PGEXPORTER_USER`, `PGEXPORTER_PASSWORD`; chart never creates the Secret |
| Test credentials | generated per run | Sourced from `test/lib/test-env.sh`; never committed |

## Behaviors

| ID | Given | When | Then |
|---|---|---|---|
| B1 | The tracked tree at any commit | The credential-literal scan runs (`test/validation/no-static-credentials-test.sh`) | Zero findings: no known credential literal and no inline chart password value path exists |
| B2 | Default chart values | `helm template` is run with no overrides | Rendering succeeds and the output contains no `kind: Secret` and no credential value; workloads reference operator-provided Secrets by name only |
| B3 | `pgexporter.enabled=true` with default credentials values | `helm template` is run | Rendering succeeds; the pgexporter Deployment references the default Secret name by reference; no Secret is rendered |
| B4 | A test or CI job needs stack credentials | The test sources `test/lib/test-env.sh` | Ephemeral values are generated for the run (or taken from the caller's environment); no literal appears in the script |

## Rules

| ID | Rule |
|---|---|
| R1 | No tracked file may contain a literal credential value — including example, test, and CI files. |
| R2 | The Helm chart MUST NOT accept an inline password value for any component and MUST NOT render a Secret. Credentials are existingSecret-references only. |
| R3 | The compose stack MUST use fail-fast environment interpolation for every credential (`${VAR:?}` with no default value). |
| R4 | Database roles created by init scripts MUST take their password from the runtime environment, never from a literal in the script. |
| R5 | Tests and CI MUST generate ephemeral credentials per run via `test/lib/test-env.sh` (respecting caller-provided values for reproduction). |
| R6 | Documentation examples MUST show only by-reference or placeholder forms (`<password>`); never a working literal. |

## Invariants

| ID | Invariant |
|---|---|
| I1 | A scan for the historical credential literals (the ban list lives in `test/validation/no-static-credentials-test.sh`) over the tracked tree returns nothing. `CHANGELOG.md` is excluded: it records the removal history in prose and is covered by gitleaks. |
| I2 | `helm template` output never contains a credential value, under any values combination shipped in the repository. |
| I3 | The scan test (B1) is wired into the local security gate (`scripts/security-checks.sh`) and CI, so a regression cannot land silently. |

## Failure conditions

| Trigger | System response |
|---|---|
| A credential literal is introduced in a tracked file | `test/validation/no-static-credentials-test.sh` fails, failing the local security gate and CI |
| Chart values reintroduce an inline password path | The scan test fails (values-key scan); `helm template` assertion fails if a Secret is rendered |
| A required compose credential variable is unset | Compose fails fast naming the variable (see `compose-pgexporter-integration` B8/AC-07) |

## Constraints

- The scan bans exact known literals and structural patterns (inline
  chart password keys, `PASSWORD '...'` literals in SQL); it is a
  tripwire, not a general-purpose secret scanner. gitleaks remains the
  general scanner (Release Protocol Gate C).
- Placeholder forms in documentation are allowed only when angle-bracketed
  (`<password>`) or clearly non-working (`CHANGEME` on non-secret fields).
