# Governance

## Project ownership

pgAgroal is maintained by [Elevarq](https://elevarq.com). The project is
open source under the BSD-3-Clause license.

## Decision making

Architectural and strategic decisions are made by the Elevarq core team.
Community input is welcome via GitHub issues and pull requests.

## Contribution process

1. Open an issue describing the proposed change
2. Discuss the approach with maintainers
3. Submit a pull request following [CONTRIBUTING.md](CONTRIBUTING.md)
4. Maintainers review and merge or request changes

## Scope boundary

This repository packages [pgagroal](https://github.com/pgagroal/pgagroal)
as a production-grade container and Helm chart. Its scope is the
container image, the Helm chart, deployment configuration, and the
supporting build/release tooling.

It is **not** the home for changes to pgagroal itself. Bugs and features
in the pooler belong upstream at the
[pgagroal project](https://github.com/pgagroal/pgagroal); security issues
in pgagroal should follow that project's disclosure process. Contributions
here that cross into upstream territory will be redirected accordingly.

## Code of conduct

We expect all participants to be respectful and constructive. Harassment,
discrimination, and abusive behavior are not tolerated. See
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
