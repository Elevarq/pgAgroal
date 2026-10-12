# Carried downstream patches

The Enterprise image builds upstream `pgagroal` from source at the tag pinned by
`PGAGROAL_VERSION` in the `Dockerfile`. The patches in `patches/` are applied to
that pinned source at build time (after `git clone`, before `cmake`), with a
fail-loud `git apply --check` guard.

These are **security fixes pending upstream acceptance**, not a fork
(ADR-0001 preserved). Each patch is removed as soon as upstream ships a release
that carries the fix and `PGAGROAL_VERSION` is bumped to it.

No reproducer or exploit detail is recorded here or in the patch files — the
patches are the hardening diffs only.

| Patch | Pinned base | What it hardens | Upstream tracking | Remove when |
|---|---|---|---|---|
| `0001-harden-client-startup-packet-parser.patch` | pgagroal 2.1.0 | Treats the **client startup-packet** parse path as a validation boundary and centralizes bounded field copies (`pgagroal_copy_bounded`) for username / database / application_name in `security.c` + `utils.c`. Prevents out-of-bounds handling of malformed startup packets on the client-facing ingress. | Validated upstream-candidate (sanitizer + regression tested). Same vulnerability **class** is public upstream in `pgagroal/pgagroal#1016`, `#1051`, `#1020` (fix PRs `#1017`/`#1052` open/unmerged). Coordinated disclosure stalled; no patched upstream release. | Upstream merges the equivalent fix **and** cuts a release; bump `PGAGROAL_VERSION` to it and delete this patch (the build guard will flag it as no-longer-applying). |

## Not yet carried (follow-up)

The **backend-facing** parse fixes are tracked separately and are **not** in this
overlay yet, because the available upstream fixes (`#1017`/`#1052`) are
third-party and need security review before they go into the paid product:

- `pgagroal/pgagroal#1016` — `query_system_identifier()` (`server.c`) / `server_probe()` (`health.c`): backend query response parsed without bounds checks.
- `pgagroal/pgagroal#1051` — `pgagroal_extract_message()` (`utils.c`): buffer walked with unchecked length fields.
- `pgagroal/pgagroal#1020` — `pgagroal_authenticate()`: memory-lifetime issue.

## Verifying a patch still applies

```bash
git clone --branch <PGAGROAL_VERSION> --depth 1 https://github.com/pgagroal/pgagroal.git
cd pgagroal
for p in ../patches/*.patch; do git apply --check "$p" && echo "OK: $p"; done
```
