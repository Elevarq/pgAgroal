# Release Checklist

Steps to cut a new release of the pgagroal container project.

## Pre-release

- [ ] All tests pass locally:
  ```bash
  make test-all
  make test-pooling
  make test-startup-failure
  make test-invalid-creds
  ```

- [ ] Helm lint passes:
  ```bash
  make helm-lint
  make helm-template
  ```

- [ ] CI pipeline is green on the release branch

- [ ] Update version strings:

  This project tracks two version numbers:
  - **Project version** (`VERSION`, git tag): the release of this container packaging
  - **pgagroal version** (`Dockerfile` ARG): the upstream pgagroal release being built

  | File | Field | Tracks | Example |
  |---|---|---|---|
  | `VERSION` | entire file | project | `1.0.0` |
  | `helm/pgagroal/Chart.yaml` | `version` | project | `1.0.0` |
  | `CHANGELOG.md` | new section | project | `## [1.0.0]` |
  | `Dockerfile` | `ARG PGAGROAL_VERSION` | pgagroal | `2.0.3` |
  | `Makefile` | `IMAGE_TAG` | pgagroal | `2.0.3` |
  | `helm/pgagroal/Chart.yaml` | `appVersion` | pgagroal | `"2.0.3"` |
  | `helm/pgagroal/values.yaml` | `image.tag` | pgagroal | `"2.0.3"` |
  | `README.md` | Pinned Versions table | both | update rows |

- [ ] If pgagroal upstream changed build dependencies, update the Dockerfile build stage

- [ ] Review `DEBIAN_VERSION` ARG -- pin to a current bookworm-slim snapshot

## Docker Hub Tagging Policy

Docker Hub image tags follow the **project version** (the `VERSION`
file), not the pgagroal upstream version. The publish workflow
(`.github/workflows/publish.yml`) derives tags automatically from the
Git tag via `docker/metadata-action`:

| Git tag | Docker Hub tags |
|---|---|
| `v1.0.0` | `1.0.0`, `1.0`, `latest` |
| `v1.0.1` | `1.0.1`, `1.0`, `latest` |
| `v1.1.0-rc1` | `1.1.0-rc1` |

Stable releases produce full version, minor alias, and `latest`.
Release candidates produce only the RC tag — they must not update
`latest`.

> **WARNING:** Do not push tags based on the pgagroal upstream version
> (e.g. `2.0.2`, `2.1.0`). These are not valid image versions. The
> pgagroal upstream version is tracked only in:
> - `Dockerfile` — `ARG PGAGROAL_VERSION`
> - `helm/pgagroal/Chart.yaml` — `appVersion`
> - `helm/pgagroal/values.yaml` — `image.tag`
>
> It must never appear as a Docker Hub tag.

Production deployments should pin to a version tag, not `latest`.

## Publish to ECR

```bash
VERSION=$(cat VERSION)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=eu-west-1
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

aws ecr get-login-password --region ${REGION} \
  | docker login --username AWS --password-stdin ${REGISTRY}

docker tag pgagroal:${VERSION} ${REGISTRY}/pgagroal:${VERSION}
docker push ${REGISTRY}/pgagroal:${VERSION}

# Optional: push major.minor alias
docker tag pgagroal:${VERSION} ${REGISTRY}/pgagroal:$(echo ${VERSION} | cut -d. -f1-2)
docker push ${REGISTRY}/pgagroal:$(echo ${VERSION} | cut -d. -f1-2)
```

## Publish to GHCR

```bash
VERSION=$(cat VERSION)
GHCR_REPO=ghcr.io/<org>/pgagroal

echo "${GITHUB_TOKEN}" | docker login ghcr.io -u <user> --password-stdin

docker tag pgagroal:${VERSION} ${GHCR_REPO}:${VERSION}
docker push ${GHCR_REPO}:${VERSION}
```

## Helm Chart Release

The Helm chart version (`Chart.yaml` `version`) is independent of the container image version (`appVersion`). Bump it when:
- Chart templates change (patch or minor bump)
- Default values change in a breaking way (major bump)
- Container image version changes (update `appVersion`, bump chart patch)

If using a Helm chart repository:

```bash
helm package helm/pgagroal/
# Upload pgagroal-<chart-version>.tgz to your chart repo
```

## Release Control Requirements

All releases must satisfy these controls:

- No image may be published to Docker Hub outside of the CI publish
  workflow. Manual `docker push` is not permitted.
- Every release must be reproducible: a given git tag must always
  produce the same image content (modulo base image layer updates).
- Post-release verification steps (below) must pass before the
  release is announced or deployed to production.
- Release tags may only be created by maintainers.

For the full security and supply chain context, see
[docs/security/supply-chain-and-release-security.md](../security/supply-chain-and-release-security.md).

## Release Flow

1. Commit version updates to `main` through the normal review process.
2. Tag and push:
   ```bash
   VERSION=$(cat VERSION)
   git tag -a "v${VERSION}" -m "Release ${VERSION}"
   git push origin "v${VERSION}"
   ```
3. The publish workflow (`.github/workflows/publish.yml`) runs
   automatically on the `v*` tag push. It builds and pushes:
   - Multi-arch image index (`linux/amd64`, `linux/arm64`)
   - SBOM attestation
   - SLSA provenance attestation (`mode=max`)
   - Cosign keyless signature (GitHub OIDC)
   - Tags: `{version}`, `{major}.{minor}`, `latest`

Do not run `docker push` manually to Docker Hub. All Docker Hub
publishing must go through the publish workflow.

## Post-release Verification

For the full evidence checklist with audit-grade commands, see
[release-evidence-checklist.md](release-evidence-checklist.md).

- [ ] Publish workflow succeeded:
  ```bash
  gh run list --workflow publish.yml --limit 1
  ```

- [ ] Multi-arch manifest is correct (both platforms present):
  ```bash
  docker buildx imagetools inspect elevarq/pgagroal:${VERSION}
  ```

- [ ] No unexpected platform images (e.g. stale Rocky artifacts):
  verify only `linux/amd64` and `linux/arm64` appear, plus
  attestation manifests

- [ ] Cosign signature verifies for the release tag:
  ```bash
  cosign verify elevarq/pgagroal:${VERSION} \
    --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
  ```

- [ ] Cosign signature verifies for `latest`:
  ```bash
  cosign verify elevarq/pgagroal:latest \
    --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
  ```

> **A release is not complete until Cosign verification succeeds.**
> If `cosign verify` returns "no signatures found", the signing step
> did not run. The most common cause is that the git tag was created
> on a commit before the Cosign step existed in the publish workflow.
> Fix: retag on a commit that includes the signing step, push the
> tag, and verify again.

- [ ] Docker Scout shows no critical/high vulnerabilities:
  ```bash
  docker scout cves registry://elevarq/pgagroal:${VERSION}
  docker scout cves registry://elevarq/pgagroal:${VERSION} --platform linux/arm64
  ```

- [ ] Update EKS deployments:
  ```bash
  helm upgrade pgagroal helm/pgagroal/ \
    --set image.tag=${VERSION} \
    -n pgagroal
  ```

- [ ] Verify the deployed version:
  ```bash
  kubectl -n pgagroal get pods -o jsonpath='{.items[*].spec.containers[0].image}'
  ```

- [ ] Monitor for errors in the first 15 minutes after deployment

## Docker Hub Documentation

The Docker Hub repository overview is maintained in `DOCKER_HUB.md` at
the repository root. After any release that changes version numbers,
features, or verification instructions:

1. Update `DOCKER_HUB.md` in the same commit or a follow-up commit.
2. Copy the contents to Docker Hub > elevarq/pgagroal > General >
   Repository overview.
3. Verify that the Quick Start example, image tags table, and
   verification commands in Docker Hub match the current release.

The `README.md` Pinned Versions table must also be updated to match.

## Version Bump After Release

After tagging, prepare the next development cycle:

1. Bump `VERSION` to the next expected version (e.g. `1.1.0`)
2. Bump `Chart.yaml` `version` to next patch (e.g. `1.1.0`)
3. Commit as "Prepare next development cycle"

## Release History

| Version | Type | Notes |
|---|---|---|
| 0.1.0 | Initial | First container packaging |
| 0.2.0-rc1 | Pre-release | Transitional release while publish/signing/docs pipeline was stabilized |
| 1.0.0 | Stable | First stable public release. Establishes the stable versioning line. |

## Release Pitfalls

Lessons learned from past incidents. Review before every release.

**Do not push Docker Hub tags manually.** Manual `docker push` to
Docker Hub creates images without SBOM, provenance, or Cosign
signatures. These images score poorly in Docker Scout and cannot be
verified by downstream users. All Docker Hub publishing must go
through the CI publish workflow.

**Do not use pgagroal upstream version as an image tag.** The Docker
Hub tags `2.1.0` and `2.1.1` were manually pushed using the upstream
version and had to be deleted. Image tags must follow the project
version (`VERSION` file). See the tagging policy above.

**Stale platform manifests persist.** If a multi-arch manifest is
pushed with mismatched platform images (e.g. amd64 from Debian, arm64
from Rocky), Docker Hub retains the stale platform entry until it is
overwritten by a new push for that platform. The fix is to always
build all platforms in a single workflow run.

**`latest` must only be managed by CI.** Never manually tag or push
`latest`. The publish workflow updates `latest` as a multi-arch
manifest on every release.

**Keep Docker Hub docs in sync.** `DOCKER_HUB.md` is the source of
truth for the Docker Hub repository overview but is not automatically
synced. After any release that changes version numbers or verification
commands, update both the file and the Docker Hub overview.
