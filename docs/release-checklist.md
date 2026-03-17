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
  | `VERSION` | entire file | project | `0.2.0` |
  | `helm/pgagroal/Chart.yaml` | `version` | project | `0.2.0` |
  | `CHANGELOG.md` | new section | project | `## [0.2.0]` |
  | `Dockerfile` | `ARG PGAGROAL_VERSION` | pgagroal | `2.0.3` |
  | `Makefile` | `IMAGE_TAG` | pgagroal | `2.0.3` |
  | `helm/pgagroal/Chart.yaml` | `appVersion` | pgagroal | `"2.0.3"` |
  | `helm/pgagroal/values.yaml` | `image.tag` | pgagroal | `"2.0.3"` |
  | `README.md` | Pinned Versions table | both | update rows |

- [ ] If pgagroal upstream changed build dependencies, update the Dockerfile build stage

- [ ] Review `DEBIAN_VERSION` ARG -- pin to a current bookworm-slim snapshot

## Image Tagging

Tag the image with both the full version and a `major.minor` alias:

```bash
VERSION=$(cat VERSION)

docker build -t pgagroal:${VERSION} .
docker tag pgagroal:${VERSION} pgagroal:$(echo ${VERSION} | cut -d. -f1-2)
```

Example: `pgagroal:2.0.3` and `pgagroal:2.0`.

Never publish a `latest` tag. Always pin.

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

## Post-release

- [ ] Git tag the release commit:
  ```bash
  VERSION=$(cat VERSION)
  git tag -a "v${VERSION}" -m "Release ${VERSION}"
  git push origin "v${VERSION}"
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

## Version Bump After Release

After tagging, prepare the next development cycle:

1. Bump `VERSION` to the next expected version (e.g. `2.0.4`)
2. Bump `Chart.yaml` `version` to next patch (e.g. `0.1.1`)
3. Commit as "Prepare next development cycle"
