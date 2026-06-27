# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, email `security@elevarq.com`. Include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within 48 hours and provide a fix timeline
within 5 business days.

## Scope

This policy covers the Elevarq pgAgroal image and chart: the container
packaging, the Helm chart, the configuration templates, and — explicitly —
**the defaults we ship and the upstream version we bundle**. We own the
security posture of the configuration this image ships with (HBA rules,
authentication defaults, network exposure, bind addresses) and of the
pgagroal version we choose to bundle, including whether a known-vulnerable
version is shipped. Reports about a weak shipped default, an exposed
endpoint, or a bundled version with a known advisory are in scope here.

Bugs in pgagroal's own source code can additionally be reported upstream to
the [pgagroal project](https://github.com/pgagroal/pgagroal); doing so does
not move the *shipped posture* out of our scope. If a bundled-version
advisory affects this image, raising it here is correct.

### Bundled upstream version

This release bundles **pgagroal 2.1.0** (Elevarq packaging v1.4.0). As of
this release there is no published CVE or GHSA against pgagroal 2.1.0 that
requires a carry-patch, so the bundled version is held at 2.1.0 deliberately
rather than for lack of maintenance. If an advisory is published against the
bundled version, we will evaluate bumping it or carrying a fix, and document
the decision in the changelog.

## Security Measures

This project implements the following security controls:

- Non-root container runtime (UID 1000)
- All Linux capabilities dropped
- `allowPrivilegeEscalation: false`
- `seccompProfile: RuntimeDefault`
- Read-only root filesystem (Kubernetes, via emptyDir for writable paths)
- `automountServiceAccountToken: false`
- Credentials injected via environment variables / Kubernetes Secrets, never baked into the image
- Base image pinned by digest (no floating `latest` tags), with a runtime security upgrade
- Multi-stage build (build tools not present in runtime image)

Hardened shipped defaults (v1.4.0):

- HBA restricted to an RFC1918 source-CIDR allowlist with `scram-sha-256` auth — not `host all all all all`
- `allow_unknown_users` defaults to `false` (unknown users are not passed through to the backend)
- Helm `NetworkPolicy` enabled by default (denies cross-namespace ingress, allows same-namespace pods)
- `docker-compose` example publishes pooler/metrics ports on `127.0.0.1` only
- pgexporter metrics listener binds `0.0.0.0` (IPv4), exposure bounded to the loopback-published port

## Supply Chain Security

Images published to Docker Hub are built exclusively by GitHub Actions
and include SBOM, SLSA provenance, and Cosign keyless signatures. For
details on build integrity, verification, and auditability, see
[docs/security/supply-chain-and-release-security.md](docs/security/supply-chain-and-release-security.md).

## Supported Versions

Security fixes are released against the latest minor version. Upgrade to the
current release to receive them.

| Version | Supported |
|---|---|
| 1.4.x | Yes |
| < 1.4.0 | No |
