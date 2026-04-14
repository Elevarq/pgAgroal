# pgagroal

Production-ready PostgreSQL connection pooler container.

- Minimal latency overhead (~0.1-0.3 ms per statement)
- Multi-architecture (amd64, arm64)
- Signed images (Cosign, keyless via GitHub OIDC)
- SBOM and SLSA provenance included
- Hardened runtime (non-root, no capabilities)

## Contents

- pgagroal 2.0.2
- Base image: debian:bookworm-20260316-slim
- Architectures: amd64, arm64

## Quick start

```bash
docker pull elevarq/pgagroal:1.0.1
```

## Verify

```bash
cosign verify elevarq/pgagroal:1.0.1 \
  --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

## Documentation

<https://elevarq.com/docs/pgagroal-container>
