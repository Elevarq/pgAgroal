# Release Process

End-to-end workflow for releasing a new version of the pgagroal container project.

## Overview

```
Refresh upstream  →  Validate  →  Prepare release  →  Tag  →  Push  →  Deploy
```

## 1. Refresh upstream version (if applicable)

```bash
make refresh-dry-run VERSION=2.1.0   # preview
make refresh VERSION=2.1.0           # update, build, test
```

See [monthly-refresh.md](monthly-refresh.md) for details.

## 2. Run validation

```bash
make test                  # integration
make test-backend-restart  # resilience
make helm-lint             # chart
make helm-template         # render
```

## 3. Update project version

Edit `VERSION` and `helm/pgagroal/Chart.yaml` `version` field:

```bash
echo "0.2.0" > VERSION
# Edit Chart.yaml: version: 0.2.0
```

Update `CHANGELOG.md` with a dated section.

## 4. Prepare release

```bash
make prepare-release
```

This checks:
- VERSION matches Chart.yaml version
- pgagroal version is consistent across Dockerfile, Makefile, Chart.yaml, values.yaml
- Working tree is clean
- On main branch
- Tag does not already exist

It then prints the exact git commands to run.

## 5. Commit, tag, push

```bash
git add -A && git commit -m "Release v0.2.0"
git tag -a v0.2.0 -m "Release v0.2.0 (pgagroal 2.1.0)"
git push origin main
git push origin v0.2.0
```

## 6. Post-release

- Verify tag on GitHub: `git ls-remote origin | grep v0.2.0`
- Push image to ECR (see [release-checklist.md](release-checklist.md))
- Deploy to EKS: `helm upgrade pgagroal helm/pgagroal/ --set image.tag=2.1.0 -n pgagroal`
- Run [post-deployment verification](../deployment/post-deployment-verification.md)

## Quick consistency check

```bash
make release-check
```

Non-interactive check that exits 0 if everything is consistent, 1 if not.
