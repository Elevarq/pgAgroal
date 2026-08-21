# Specification: Frontend TLS (client ↔ pooler)

## Status

ACTIVE (#103; added for v1.4.5)

## Purpose

Allow operators to enable TLS on the **frontend** connection — the hop between
clients and the pgagroal pooler — so client↔pooler traffic can be encrypted
(optionally with client-certificate / mutual TLS). Upstream pgagroal supports
this in the main `[pgagroal]` section (`tls`, `tls_cert_file`, `tls_key_file`,
`tls_ca_file`, `tls_cert_auth_mode`); this feature drives those keys from
environment variables and installs the certificate material with the file
permissions pgagroal requires.

**Scope: frontend TLS only.** Backend TLS (pooler → PostgreSQL) is upstream-marked
"Experimental — no pooling" and disabling pooling defeats the product, so it is
NOT configured here. It remains a private-network / TLS-terminating-sidecar concern
and is out of scope.

## Interfaces

### Inputs

| Input | Type | Default | Constraints |
|-------|------|---------|-------------|
| `PGAGROAL_TLS` (env) / `pgagroal.tls.enabled` (Helm) | bool-string | `off` | Enable value: `on`/`true`/`1`/`yes`. Disable value: `off`/`false`/`0`/`no`. Any OTHER value (a typo) is rejected — it does not silently disable TLS. |
| `PGAGROAL_TLS_CERT_FILE` (env) | path | — | Server certificate (PEM). REQUIRED when TLS is enabled; must exist and be readable. |
| `PGAGROAL_TLS_KEY_FILE` (env) | path | — | Server private key (PEM). REQUIRED when TLS is enabled; must exist and be readable. |
| `PGAGROAL_TLS_CA_FILE` (env) | path | — | CA bundle (PEM) for client-certificate (mutual) TLS. Optional; when set, pgagroal requires and verifies a client certificate against the CA. |
| `PGAGROAL_TLS_CERT_AUTH_MODE` (env) / `pgagroal.tls.certAuthMode` (Helm) | string | `verify-ca` | Only `verify-ca` is supported. The pgagroal **pooler** has no `tls_cert_auth_mode` key (it is a pgagroal-*vault* setting), so `verify-full`/CN-SAN matching is NOT available and is rejected. |

### Outputs

- `pgagroal.conf` `[pgagroal]` section contains, **only when TLS is enabled**:
  `tls = on`, `tls_cert_file = <installed cert>`, `tls_key_file = <installed key>`,
  and, when a CA is provided, `tls_ca_file = <installed ca>`. **No
  `tls_cert_auth_mode` line is ever emitted** (the pooler does not support it).
- Installed certificate material under a writable directory
  (`${CONF_DIR}/tls/{server.crt,server.key,ca.crt}`) with the private key at
  mode `0600`.

## Behaviors

- **B1** — Given `PGAGROAL_TLS` a disable value (off/false/0/no or unset), when
  `pgagroal.conf` is rendered, then it contains no `tls*` keys (behavior is
  unchanged from a non-TLS build).
- **B2** — Given `PGAGROAL_TLS` an enable value with cert + key, when the config is
  rendered, then the `[pgagroal]` section contains `tls = on`, `tls_cert_file`, and
  `tls_key_file` pointing at the installed paths; no `tls_ca_file` line is present.
- **B3** — Given `PGAGROAL_TLS` an enable value with cert + key + CA, when the config
  is rendered, then it additionally contains `tls_ca_file` — and never
  `tls_cert_auth_mode`.
- **B4** — Given `PGAGROAL_TLS` enabled, when the entrypoint installs certificate
  material, then the private key is written with mode `0600` regardless of the
  source file's permissions.
- **B5** — Given `PGAGROAL_TLS` enabled but `PGAGROAL_TLS_CERT_FILE` or
  `PGAGROAL_TLS_KEY_FILE` unset, missing, or unreadable, when the entrypoint runs,
  then it exits non-zero with a message naming the missing input, before starting
  pgagroal (fail closed).
- **B6** — Given `PGAGROAL_TLS` set to a value that is neither a known enable nor a
  known disable value (a typo), when the entrypoint runs, then it exits non-zero
  before starting pgagroal (fail closed — never a silent plaintext listener).
- **B7** — Given `PGAGROAL_TLS_CERT_AUTH_MODE=verify-full`, or `PGAGROAL_TLS_CERT_AUTH_MODE`
  set without a CA, when the entrypoint runs, then it exits non-zero.

## Rules

- **R1** — TLS is enabled iff `PGAGROAL_TLS` matches (case-insensitively)
  `on`/`true`/`1`/`yes`; disabled iff it matches `off`/`false`/`0`/`no` (or is
  unset). Any other value is rejected (B6) rather than treated as disabled.
- **R2** — The pooler `[pgagroal]` section supports `tls`, `tls_cert_file`,
  `tls_key_file`, and `tls_ca_file` only. `tls_cert_auth_mode` is **never** emitted;
  `PGAGROAL_TLS_CERT_AUTH_MODE` accepts only `verify-ca`, and `verify-full` is
  rejected as unsupported.
- **R3** — The installed private key is mode `0600`; the certificate and CA are
  world-readable (`0644`).

## Invariants

- **I1** — When TLS is disabled, the rendered `pgagroal.conf` is byte-identical to
  the pre-feature output (no TLS keys leak in).
- **I2** — TLS is a transport concern only: enabling it never changes which users
  are accepted, HBA source restriction, or backend authentication.
- **I3** — The private key is never rendered into the config or logs; only its
  installed file path appears.

## Failure conditions

| Trigger | Response |
|---------|----------|
| `PGAGROAL_TLS` enabled and cert or key missing/unreadable | Entrypoint exits non-zero with a message naming the missing file; pgagroal is not started. |
| `PGAGROAL_TLS` set to an unrecognized value (typo) | Entrypoint exits non-zero; never a silent plaintext listener. |
| `PGAGROAL_TLS_CERT_AUTH_MODE=verify-full` (unsupported by the pooler) | Entrypoint exits non-zero. |
| `PGAGROAL_TLS_CERT_AUTH_MODE` set without a CA | Entrypoint exits non-zero. |

## Constraints / NFR

- The image and the Helm chart MUST configure TLS identically (same template, same
  entrypoint). The Helm chart supplies cert/key/CA via a referenced Secret.
- No new port: TLS uses the existing pooler port (`PGAGROAL_PORT`, default 6432).
- Backend TLS remains out of scope (upstream experimental / disables pooling).
