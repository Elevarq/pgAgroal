# Transaction Pooling Proof Plan

Evidence-based validation plan for migrating Java/Hibernate applications
from session pooling (or direct connection) to pgagroal transaction pooling.

## Phases

```
Phase 1: Static Analysis  →  Phase 2: Lab Validation  →  Phase 3: Canary  →  Phase 4: Rollout
```

Each phase has gates. An application that fails a gate stays on session pooling.

Track progress across all applications in the [assessment index](transaction-pooling-assessment-index.md).

---

## Phase 1: Static Analysis (per application)

**Duration**: 1-2 hours per application.

1. Copy the [assessment template](transaction-pooling-app-assessment-template.md) for the application:
   ```bash
   cp docs/operations/transaction-pooling-app-assessment-template.md docs/operations/assessment-<app-name>.md
   ```
2. Fill in the application profile section
3. Complete the [compatibility checklist](java-hibernate-compatibility-checklist.md) and record results in the assessment
4. Produce a disposition for each risk area: compatible / incompatible / needs mitigation
5. If incompatible patterns are found, log them in the "Risky Patterns Found" table

**Gate**: all checklist items pass or have documented mitigations applied.

---

## Phase 2: Lab Validation

**Duration**: 1 day per application.

### Environment setup

```
App  →  HikariCP  →  pgagroal (pipeline=transaction)  →  PostgreSQL
```

pgagroal config additions for transaction mode:

```ini
pipeline = transaction
track_prepared_statements = on
```

### 2a. Test suite execution

Run the application's existing test suite twice:

1. **Baseline**: with `pipeline = session` (or direct connection)
2. **Transaction mode**: with `pipeline = transaction`

Compare:
- Total pass/fail count
- List of failures unique to transaction mode
- Any flaky tests

**Gate**: zero new failures in transaction mode.

### 2b. pg_stat_activity monitoring

During the test suite run, sample `pg_stat_activity` every 5 seconds:

```bash
# Run in a separate terminal during tests
scripts/sampling/pg-stat-sampler.sh --interval 5 --output /tmp/stat_activity.csv
```

Review for:
- SET commands in the `query` column between transactions
- Backend connections holding state after commit
- Connection count trajectory

**Gate**: no session-state leakage detected.

### 2c. Connection count comparison

Run a realistic workload (or the test suite under concurrency) in both modes.
Sample connection counts:

```bash
# During session pooling
scripts/sampling/connection-count.sh --interval 2 --duration 120 --output session.csv

# During transaction pooling
scripts/sampling/connection-count.sh --interval 2 --duration 120 --output transaction.csv
```

Compare peak and average backend connection counts.

**Gate**: transaction mode shows measurably fewer backend connections.

### 2d. Latency and error comparison

Measure from the application side:
- HTTP response latency (P50, P95, P99)
- JDBC exception count
- 5xx error rate

**Gate**: P50 increase < 5%, P99 increase < 20%, no new error types.

### 2e. Backend restart under load

While the application is under load through pgagroal transaction mode:

1. Restart the PostgreSQL backend
2. Measure recovery time (first successful request after restart)
3. Check for connection leaks

**Gate**: recovery within 30s, no leak.

### 2f. Failure injection (abnormal disconnect)

1. Start application under load
2. Kill an application instance abruptly (`kill -9`)
3. Monitor pgagroal backend connection count for 60s

**Gate**: connection count stabilizes (no unbounded growth).
Note: pgagroal#503 may cause this to fail. Document if so.

---

## Phase 3: Canary Rollout

**Duration**: 1 week per application.

Deploy transaction pooling for a subset of traffic:

1. Deploy a separate pgagroal instance with `pipeline = transaction`
2. Route 10% of application pods to the transaction-mode pooler
3. Monitor for 1 week

### Metrics to compare (canary vs. control)

| Metric | Source | Alert threshold |
|---|---|---|
| HTTP 5xx rate | Application metrics | > 0.1% above control |
| JDBC exception count | Application logs | Any new exception types |
| P99 latency | Application metrics | > 20% above control |
| Backend connection count | pg_stat_activity | Growing beyond max_connections |
| pgagroal pod restarts | Kubernetes | > 0 unexpected |

**Gate**: 1 week with no alerts triggered.

---

## Phase 4: Full Rollout

Switch the application's pgagroal deployment to `pipeline = transaction`:

```yaml
# In Helm values
pgagroal:
  pipeline: transaction
  trackPreparedStatements: on
```

Monitor for 48 hours with the same metrics as Phase 3.

---

## Per-Application Validation Matrix

| Application | Phase 1 | Phase 2a | Phase 2b | Phase 2c | Phase 2d | Phase 2e | Phase 2f | Phase 3 | Decision |
|---|---|---|---|---|---|---|---|---|---|
| App 1 | | | | | | | | | |
| App 2 | | | | | | | | | |
| App 3 | | | | | | | | | |

Mark each cell: PASS / FAIL / SKIP (with reason).

---

## Evidence Required per Application

| Evidence | Format | Retention |
|---|---|---|
| Compatibility checklist | Filled checklist (.md) | Git |
| Baseline test report | JUnit XML or summary | Attached to validation issue |
| Transaction mode test report | JUnit XML or summary | Attached to validation issue |
| pg_stat_activity samples | CSV snapshots | 30 days |
| Connection count time series | CSV or Grafana screenshot | 30 days |
| Latency comparison | P50/P95/P99 table | Git |
| Error rate comparison | Counts | Git |
| Canary week metrics | Dashboard screenshot | 30 days |
| Go/no-go decision | Signed-off checklist | Git |

---

## Evidence That Blocks Rollout

Any of these findings blocks transaction pooling for the affected application:

1. SET statements executed outside transactions that cannot be moved
2. Session-scoped advisory locks (`pg_advisory_lock`) that cannot be changed to `pg_advisory_xact_lock`
3. Temporary tables used across transaction boundaries
4. LISTEN/NOTIFY usage
5. `hibernate.connection.handling_mode = DELAYED_ACQUISITION_AND_HOLD`
6. Test suite regressions that reproduce consistently in transaction mode
7. Connection count growth after failure injection (pgagroal#503)
8. Data corruption in any test
