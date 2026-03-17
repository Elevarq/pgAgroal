# GitHub Repository Setup

Reference for configuring the GitHub repository for public release.

## Repository description

```
Production-grade Docker container and Helm chart for pgagroal PostgreSQL connection pooler
```

## Topics

```
postgresql pgagroal connection-pooling kubernetes helm database-infrastructure docker eks aws
```

## Visibility

- Start as **private** for internal validation
- Switch to **public** when ready for external consumption

To change: Settings > Danger Zone > Change visibility

## Branch protection (recommended)

- Protect `main` branch
- Require pull request reviews before merging
- Require status checks to pass (CI pipeline)
- Do not allow force pushes

## Release naming convention

| Type | Format | Example |
|---|---|---|
| Git tag | `v<project-version>` | `v0.2.0` |
| GitHub release title | `v<project-version>` | `v0.2.0` |
| Release notes | Auto-generated from CHANGELOG.md | -- |

## Labels (suggested)

| Label | Color | Description |
|---|---|---|
| `bug` | `#d73a4a` | Something isn't working |
| `enhancement` | `#a2eeef` | New feature or request |
| `documentation` | `#0075ca` | Improvements to documentation |
| `helm` | `#7057ff` | Helm chart changes |
| `container` | `#e4e669` | Dockerfile or image changes |
| `ci` | `#bfd4f2` | CI/CD pipeline |
