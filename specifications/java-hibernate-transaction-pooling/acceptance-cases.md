# Acceptance Cases: Java/Hibernate Transaction Pooling Compatibility

Derived from `spec.md`. Each case maps to a risk area and a pass/fail
criterion.

---

## Static Analysis Cases

### SA-01: No session-level SET statements

**Given**: application source code and Hibernate configuration
**When**: searched for SET patterns
**Then**:
- No `SET search_path`, `SET statement_timeout`, `SET work_mem` outside transactions
- No `hibernate.default_schema` that triggers implicit SET
- No Spring `@PostConstruct` or connection init hooks that issue SET
- OR: all SET usage is inside `@Transactional` methods (acceptable)

**Evidence**: grep results + line-by-line disposition

### SA-02: No session-scoped temporary tables

**Given**: application source code
**When**: searched for temp table creation
**Then**:
- No `CREATE TEMP TABLE` or `CREATE TEMPORARY TABLE`
- No Hibernate mappings to temporary tables
- OR: all temp tables use `ON COMMIT DROP` inside explicit transactions

**Evidence**: grep results

### SA-03: No session-level advisory locks

**Given**: application source code
**When**: searched for advisory lock usage
**Then**:
- No `pg_advisory_lock()` or `pg_try_advisory_lock()` (session-scoped)
- OR: only `pg_advisory_xact_lock()` / `pg_try_advisory_xact_lock()` (transaction-scoped, safe)

**Evidence**: grep results

### SA-04: Prepared statement tracking is enabled

**Given**: pgagroal config for transaction mode
**When**: config reviewed
**Then**:
- `track_prepared_statements = on` is set in pgagroal.conf

**Evidence**: config file content

### SA-05: Connection handling mode is compatible

**Given**: application Hibernate configuration
**When**: `hibernate.connection.handling_mode` is checked
**Then**:
- Value is NOT `DELAYED_ACQUISITION_AND_HOLD`
- OR: value is absent (Spring Boot default is safe)

**Evidence**: application.properties/yml content

### SA-06: No cross-transaction state assumptions in batch jobs

**Given**: application batch job code (Spring Batch, @Scheduled)
**When**: reviewed for connection affinity patterns
**Then**:
- Each batch step runs in its own transaction
- No state (temp tables, session variables) is carried between steps

**Evidence**: code review notes

---

## Runtime Validation Cases

### RT-01: Test suite passes under transaction pooling

**Given**: pgagroal lab with `pipeline = transaction`
**When**: application's existing test suite runs
**Then**:
- Same pass count as baseline (session pooling or direct)
- No new failures
- No test result flakiness not present in baseline

**Evidence**: test report diff (baseline vs. transaction pooling)

### RT-02: No SET leakage in pg_stat_activity

**Given**: application running under transaction pooling
**When**: `pg_stat_activity` is sampled during test suite execution
**Then**:
- No connections show `SET` commands in `query` field between transactions
- `application_name` may vary across requests (expected in tx pooling)

**Evidence**: pg_stat_activity snapshots

### RT-03: Backend connection count is lower than session pooling

**Given**: same workload, same duration
**When**: run under transaction pooling vs. session pooling
**Then**:
- Peak `pg_stat_activity` count (excluding superuser) is lower in tx mode
- Ratio is at least 2:1 improvement (app connections vs. backend connections)
  or documented justification if lower

**Evidence**: connection count time series (both modes)

### RT-04: Error rate is not higher than session pooling

**Given**: same workload, same duration
**When**: run under transaction pooling vs. session pooling
**Then**:
- HTTP error rate (5xx) is not higher in tx mode
- JDBC exception count is not higher in tx mode
- No new exception types appear in tx mode

**Evidence**: error logs / metrics comparison

### RT-05: Latency is acceptable

**Given**: same workload
**When**: run under both modes
**Then**:
- P50 latency increase is < 5%
- P99 latency increase is < 20%
- No new latency outliers (> 10s) appear

**Evidence**: latency distribution comparison

### RT-06: Backend restart recovery under transaction pooling

**Given**: pgagroal in transaction mode, application running
**When**: PostgreSQL backend is restarted
**Then**:
- Application recovers within 30 seconds
- No data corruption
- Connection pool recovers (no leak)

**Evidence**: test log with timestamps

---

## Failure Injection Cases

### FI-01: Abrupt client disconnect under load

**Given**: application under load via pgagroal transaction mode
**When**: a client process is killed mid-request
**Then**:
- pgagroal does not crash
- Other clients continue to succeed
- Backend connection count does not grow unboundedly
  (note: pgagroal#503 means this may fail — document if so)

**Evidence**: connection count log + error log

### FI-02: Connection exhaustion behavior

**Given**: `max_connections = 10`, application sending > 10 concurrent requests
**When**: pool is saturated
**Then**:
- Excess clients block for up to `blocking_timeout` (30s)
- Clients receive a clear timeout error (not hang indefinitely)
- Pool recovers after load subsides

**Evidence**: client-side error log + pgagroal status output

---

## Go/No-Go Gate

| Gate | Pass condition | Fail condition |
|---|---|---|
| G1: Static analysis | All SA-01..SA-06 pass or have documented mitigations | Any SA case fails without mitigation |
| G2: Test suite | RT-01 passes (zero regressions) | New test failures |
| G3: No state leaks | RT-02 passes | SET or temp table leakage detected |
| G4: Connection reduction | RT-03 shows measurable improvement | No improvement (no point in tx pooling) |
| G5: Error rate | RT-04 passes | Higher error rate |
| G6: Latency | RT-05 passes | Unacceptable latency increase |
| G7: Resilience | RT-06 passes | No recovery after backend restart |

**Go**: all gates pass.
**No-go**: any gate fails. Document the specific failure and use session pooling.
