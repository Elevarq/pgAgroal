# Contributing

Contributions are welcome. This document describes how to get started.

## Development Setup

1. Clone the repository
2. Ensure Docker and Docker Compose are installed
3. Build and run the stack:

```bash
make build
make run
```

## Making Changes

1. Create a feature branch from `main`
2. Make your changes
3. Run the full test suite:

```bash
make test-all
```

4. If you modified the Helm chart, also run:

```bash
make helm-lint
make helm-template
```

5. Commit with a clear message describing the change
6. Open a pull request against `main`

## Code Style

- Shell scripts: follow ShellCheck recommendations, use `set -euo pipefail`
- Dockerfile: follow hadolint recommendations
- Helm templates: use the existing helper patterns in `_helpers.tpl`
- YAML: 2-space indent, no trailing whitespace

## Tests

Every user-facing behavior change should include a test. Test scripts go in `test/` and should:

- Be self-contained (build, start, verify, clean up)
- Use `trap cleanup EXIT` for reliable teardown
- Exit 0 on success, non-zero on failure
- Print clear pass/fail messages

## Versioning

This project uses two version numbers:

- **Project version** (`VERSION`): follows semver, tracked via git tags (`v0.1.0`)
- **pgagroal version** (`Dockerfile` `ARG PGAGROAL_VERSION`): upstream pgagroal release

See [docs/release/release-checklist.md](docs/release-checklist.md) for the release procedure.

## License

By contributing, you agree that your contributions will be licensed under the BSD-3-Clause license.
