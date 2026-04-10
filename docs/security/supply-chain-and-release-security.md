# Supply Chain and Release Security

Controls and practices for build integrity, supply chain security, and
release auditability. Designed to support SOC 2 and ISO 27001 readiness
at the repository level.

## Build Integrity

- Images are built exclusively by GitHub Actions
  (`.github/workflows/publish.yml`).
- Manual `docker push` to Docker Hub is not permitted.
- Every published image is traceable to a git tag, commit SHA, and
  workflow run.
- `latest` is managed only by CI. It must never be pushed manually.

## Version Control and Traceability

- Git tags (`v{version}`) are the source of truth for releases.
- The publish workflow is triggered only by `v*` tag pushes.
- Each image can be traced to:
  - **Commit SHA** — embedded in OCI labels
    (`org.opencontainers.image.revision`)
  - **Workflow run** — linked from the GitHub Actions run history
  - **Image digest** — the immutable content-addressable identifier

## Supply Chain Attestations

Every published image includes:

| Attestation | Standard | How |
|---|---|---|
| SBOM | SPDX | `docker/build-push-action` with `sbom: true` |
| Provenance | SLSA (`mode=max`) | `docker/build-push-action` with `provenance: mode=max` |
| Signature | Sigstore / Cosign | Keyless signing via GitHub OIDC (`sigstore/cosign-installer`) |

## Verification Model

Consumers can verify image integrity before deployment:

```bash
# Verify Cosign signature
cosign verify elevarq/pgagroal:<tag> \
  --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"

# Inspect attestations
docker buildx imagetools inspect elevarq/pgagroal:<tag>
```

Production deployments should pin a version tag, not `latest`.

## Access Control

| Resource | Access |
|---|---|
| GitHub repository | Restricted to maintainers |
| Docker Hub push | CI credentials only (`DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` in GitHub Actions secrets) |
| Git tag creation | Maintainers only |
| Workflow trigger | Automated on tag push; no manual dispatch |

No shared credentials are used. Docker Hub tokens are scoped to the
`elevarq` namespace.

## Secrets Handling

- Secrets are stored exclusively in GitHub Actions encrypted secrets.
- No secrets exist in the repository source code.
- No secrets are baked into Docker images.
- `gitleaks` and Trivy secret scanning run in CI.

## Release Responsibility

- Only maintainers may create release tags.
- All releases must pass through the CI publish workflow.
- No image may be published to Docker Hub outside of CI.

## Auditability

An auditor can verify any published image:

1. **Identify the source commit:**
   ```bash
   docker buildx imagetools inspect elevarq/pgagroal:<tag> --raw \
     | jq -r '.manifests[0].annotations["org.opencontainers.image.revision"]'
   ```

2. **Locate the workflow run:**
   ```bash
   gh run list --repo Elevarq/pgAgroal --workflow publish.yml \
     --json databaseId,headSha,conclusion \
     --jq '.[] | select(.headSha == "<commit-sha>")'
   ```

3. **Verify the signature:**
   ```bash
   cosign verify elevarq/pgagroal:<tag> \
     --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
     --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
   ```

4. **Confirm SBOM and provenance exist:**
   ```bash
   docker buildx imagetools inspect elevarq/pgagroal:<tag>
   ```
   Attestation manifests (`vnd.docker.reference.type:
   attestation-manifest`) must be present for each platform.

## Known Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Manual image push bypasses controls | CI-only publishing; no manual `docker push` permitted |
| Stale multi-arch manifests | All platforms built in a single CI run; overwrites previous manifests |
| Vulnerable base image | Rebuild on new release; CVE scanning via Docker Scout and Trivy |
| Supply chain tampering | Cosign signature verification; SLSA provenance attestation |
| Credential leakage | Secrets in GitHub Actions only; gitleaks and Trivy secret scanning in CI |
| Docker Hub docs drift | `DOCKER_HUB.md` is the source of truth; update process documented in release checklist |
