# Release Evidence Checklist

Verification steps to confirm a release is complete, correct, and
auditable. Run after every release tag push.

Replace `${VERSION}` with the release version (e.g. `0.2.0`).

---

## 1. Git Tag and Commit Traceability

- [ ] Tag exists and points to the expected commit:
  ```bash
  git show v${VERSION} --no-patch
  ```
- [ ] Tag is on `main`:
  ```bash
  git branch --contains v${VERSION}
  ```
- [ ] Tag is pushed to remote:
  ```bash
  git ls-remote origin refs/tags/v${VERSION}
  ```

## 2. GitHub Actions Run Evidence

- [ ] Publish workflow completed successfully:
  ```bash
  gh run list --repo Elevarq/pgAgroal --workflow publish.yml --limit 3
  ```
- [ ] Workflow run matches the tagged commit:
  ```bash
  gh run list --repo Elevarq/pgAgroal --workflow publish.yml \
    --json databaseId,headSha,conclusion \
    --jq '.[] | select(.conclusion == "success") | {id: .databaseId, sha: .headSha}'
  ```
- [ ] No warnings or errors in workflow annotations:
  ```bash
  gh run view <run-id> --repo Elevarq/pgAgroal
  ```

## 3. Docker Image and Multi-arch Verification

- [ ] Image manifest exists and contains both platforms:
  ```bash
  docker buildx imagetools inspect elevarq/pgagroal:${VERSION}
  ```
- [ ] Confirm `linux/amd64` and `linux/arm64` are both present
- [ ] No unexpected platform entries (e.g. stale Rocky artifacts)
- [ ] `latest` tag updated and matches the release digest:
  ```bash
  docker buildx imagetools inspect elevarq/pgagroal:latest
  ```

## 4. Cosign Signature Verification

- [ ] Signature verifies against GitHub OIDC identity:
  ```bash
  cosign verify elevarq/pgagroal:${VERSION} \
    --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
  ```
- [ ] Verify `latest` is also signed:
  ```bash
  cosign verify elevarq/pgagroal:latest \
    --certificate-identity-regexp "https://github.com/Elevarq/pgAgroal/.*" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
  ```

## 5. SBOM and Provenance Attestations

- [ ] Attestation manifests present for each platform:
  ```bash
  docker buildx imagetools inspect elevarq/pgagroal:${VERSION} --raw | \
    python3 -c "
  import json, sys
  idx = json.load(sys.stdin)
  for m in idx.get('manifests', []):
      ann = m.get('annotations', {})
      ref = ann.get('vnd.docker.reference.type', '')
      plat = m.get('platform', {})
      arch = plat.get('architecture', '?')
      if ref:
          print(f'  attestation: {ref}  arch={arch}')
      else:
          print(f'  image: {plat.get(\"os\",\"?\")}/{arch}')
  "
  ```
- [ ] Output shows `attestation-manifest` entries for both amd64 and arm64

## 6. Docker Scout Vulnerability Check

- [ ] No CRITICAL or HIGH vulnerabilities:
  ```bash
  docker scout cves registry://elevarq/pgagroal:${VERSION}
  ```
- [ ] arm64 platform specifically clean:
  ```bash
  docker scout cves registry://elevarq/pgagroal:${VERSION} --platform linux/arm64
  ```
- [ ] Scout confirms SBOM was obtained from attestation (look for
  "SBOM obtained from attestation" in output)

## 7. Registry Hygiene

- [ ] No stale or unintended tags on Docker Hub:
  ```bash
  docker buildx imagetools inspect elevarq/pgagroal:latest --raw | \
    python3 -c "
  import json, sys
  idx = json.load(sys.stdin)
  print(f'{len([m for m in idx[\"manifests\"] if not m.get(\"annotations\",{}).get(\"vnd.docker.reference.type\")])} image(s)')
  print(f'{len([m for m in idx[\"manifests\"] if m.get(\"annotations\",{}).get(\"vnd.docker.reference.type\")])} attestation(s)')
  "
  ```
- [ ] Expected: 2 images (amd64, arm64) + attestation manifests
- [ ] No tags from the wrong version line remain (e.g. `2.1.0`, `2.1.1`)

## 8. Documentation Alignment

- [ ] `README.md` Pinned Versions table matches the release
- [ ] `DOCKER_HUB.md` references the current version
- [ ] Docker Hub repository overview matches `DOCKER_HUB.md`
- [ ] `CHANGELOG.md` has an entry for this release
- [ ] `VERSION` file matches the tagged version
