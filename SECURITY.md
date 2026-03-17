# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, email the maintainers directly. Include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within 48 hours and aim to provide a fix within 7 days for critical issues.

## Scope

This policy covers the container packaging, Helm chart, and configuration templates in this repository. It does **not** cover vulnerabilities in pgagroal itself -- those should be reported to the [pgagroal project](https://github.com/pgagroal/pgagroal).

## Security Measures

This project implements the following security controls:

- Non-root container runtime (UID 1000)
- All Linux capabilities dropped
- `allowPrivilegeEscalation: false`
- `seccompProfile: RuntimeDefault`
- Read-only root filesystem (Kubernetes, via emptyDir for writable paths)
- `automountServiceAccountToken: false`
- Credentials injected via environment variables / Kubernetes Secrets, never baked into the image
- Pinned base image versions (no floating `latest` tags)
- Multi-stage build (build tools not present in runtime image)

## Supported Versions

| Version | Supported |
|---|---|
| 0.1.x | Yes |
