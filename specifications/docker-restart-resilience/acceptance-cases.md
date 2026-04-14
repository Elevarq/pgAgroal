# Acceptance Cases: Container Survives `docker restart`

Derived from `spec.md`. Each case maps to behaviors, rules, or
invariants in the specification.

## AC-01: Fresh start — baseline

**Spec refs**: B1, I3

**Given**: a freshly built image, no prior container on the host
**When**: `docker run -d --name pgagroal-test ...`
**Then**:
- Container reaches `healthy` within the configured healthcheck window
- `/tmp/pgagroal.6432.pid` exists inside the running container (pgagroal
  created it)

## AC-02: Restart after ungraceful termination — stale PID file present

**Spec refs**: B2, R1, R2, I1

**Given**: a container that has been running, then terminated via
SIGKILL (simulating stop-grace expiry, OOM, or host crash), with a
stale `/tmp/pgagroal.6432.pid` left behind on the writable layer.
Confirmed stale by committing the stopped container to an image and
inspecting `/tmp`.
**When**: `docker start <container>`
**Then**:
- Container returns to `healthy` within the healthcheck window
- A SQL query via pgagroal succeeds (end-to-end proof the restart worked)
- pgagroal logs do NOT contain `PID file ... exists, is there another instance running`
- Exit code 0 from the test harness

**This is the regression test for the defect described in the spec.**
Without the entrypoint guard, `docker start` fails with the PID-file
conflict message and the container becomes unhealthy (exit 1).

## AC-03: Clean shutdown on SIGTERM + restart

**Spec refs**: B3, B4

**Given**: a running, healthy container
**When**: `docker stop <container>` (default SIGTERM within grace),
followed by `docker start <container>`
**Then**:
- First stop: container exits within the grace period, exit code 0
- Second start: container returns to `healthy`
- Entrypoint guard executes as a no-op (PID file already absent)

## AC-04: Unix socket files are not touched by the entrypoint guard

**Spec refs**: R3

**Given**: the entrypoint guard removes the stale PID file
**When**: inspecting the `rm` pattern in `entrypoint.sh`
**Then**:
- The command targets exactly `/tmp/pgagroal.${PGAGROAL_PORT}.pid`
- The command does NOT use a glob that would also match socket files
  (e.g. `/tmp/pgagroal.*`, `/tmp/*`)
- Verified by inspection; no runtime test required
