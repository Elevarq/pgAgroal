# Acceptance Cases: Frontend TLS (client ↔ pooler)

Derived from `spec.md`. Each case maps to behaviors, rules, or invariants.
Verified by `test/validation/tls-frontend-test.sh` (dockerless: sources the
entrypoint and exercises `tls_enabled` + `build_tls_lines` + `install_tls_material`
+ envsubst rendering, with throwaway PEM files).

## AC-01: TLS off by default — no TLS keys rendered

**Spec refs**: B1, I1

**Given**: `PGAGROAL_TLS` unset
**When**: `pgagroal.conf` is rendered
**Then**: it contains no `tls`, `tls_cert_file`, `tls_key_file`, `tls_ca_file`, or
`tls_cert_auth_mode` line.

## AC-02: `tls_enabled` truthiness

**Spec refs**: R1

**Given**: `PGAGROAL_TLS` in {on, true, 1, yes, ON, True}
**Then**: `tls_enabled` succeeds; and for {off, false, 0, no, "", garbage} it fails.

## AC-03: cert + key only

**Spec refs**: B2

**Given**: TLS on with cert + key (no CA)
**When**: `build_tls_lines` runs
**Then**: output has `tls = on`, `tls_cert_file = <dir>/server.crt`,
`tls_key_file = <dir>/server.key`, and no `tls_ca_file` / `tls_cert_auth_mode`.

## AC-04: cert + key + CA (mutual TLS) — no auth-mode key

**Spec refs**: B3, R2

**Given**: TLS on with cert + key + CA
**When**: `build_tls_lines` runs
**Then**: output additionally has `tls_ca_file = <dir>/ca.crt` and **never**
`tls_cert_auth_mode` (the pooler has no such key).

## AC-05: verify-full is rejected

**Spec refs**: B7, R2

**Given**: TLS on with CA and `PGAGROAL_TLS_CERT_AUTH_MODE=verify-full`
**When**: `build_tls_lines` runs
**Then**: it returns non-zero (verify-full is unsupported by the pgagroal 2.1.0
pooler) and emits no config.

## AC-06: key installed at 0600

**Spec refs**: B4, R3

**Given**: TLS on; a source key file with mode 0644
**When**: `install_tls_material` runs
**Then**: the installed key is mode `0600` and the installed cert is `0644`.

## AC-07: fail closed on missing material

**Spec refs**: B5

**Given**: TLS on but `PGAGROAL_TLS_KEY_FILE` points at a nonexistent path
**When**: `install_tls_material` runs
**Then**: it returns non-zero and names the missing key file.

## AC-08: invalid auth mode rejected

**Spec refs**: failure conditions

**Given**: TLS on with CA and `PGAGROAL_TLS_CERT_AUTH_MODE=bogus`
**When**: `build_tls_lines` (validation) runs
**Then**: it returns non-zero naming `verify-ca`/`verify-full`.

## AC-09: TLS lines render into the [pgagroal] section

**Spec refs**: B2, I2

**Given**: TLS on with cert + key, and `PGAGROAL_TLS_LINES` exported
**When**: `pgagroal.conf.template` is rendered with `envsubst`
**Then**: the `[pgagroal]` section contains the `tls = on` block and the `[primary]`
section is unchanged.

## AC-10: fail closed on an unknown `PGAGROAL_TLS` value

**Spec refs**: B6, R1

**Given**: `PGAGROAL_TLS` set to a typo (`tru`, `enabled`, `on ` …)
**When**: `validate_tls_setting` runs
**Then**: it returns non-zero (known enable/disable values pass); the entrypoint
never starts a plaintext listener for a typo.

## AC-11: cert-auth-mode without a CA is rejected

**Spec refs**: B7

**Given**: `PGAGROAL_TLS_CERT_AUTH_MODE` set with no `PGAGROAL_TLS_CA_FILE`
**When**: `validate_tls_setting` runs
**Then**: it returns non-zero.

## AC-12: Helm wires TLS (not just env)

**Spec refs**: Constraints/NFR

**Given**: `helm template` with `tls.enabled=true` + `tls.existingSecret`
**When**: the chart renders
**Then**: the ConfigMap carries `${PGAGROAL_TLS_LINES}`; the Deployment sets
`PGAGROAL_TLS`, the cert/key env, mounts the Secret at `/etc/pgagroal/tls-src`, and
adds the Secret volume. Verified by `test/validation/helm-tls-render-test.sh`.
