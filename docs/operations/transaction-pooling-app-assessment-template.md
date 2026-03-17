# Transaction Pooling Assessment: [APP NAME]

> Copy this file per application:
> `cp docs/operations/transaction-pooling-app-assessment-template.md docs/operations/assessment-<app-name>.md`

## Application Profile

| Field | Value |
|---|---|
| Application name | |
| Owner / team | |
| Repository | |
| Framework | Spring Boot __ / Hibernate __ / Java __ |
| JDBC driver version | |
| Application-side pool | HikariCP __ (maximumPoolSize: __) |
| Current topology | App → HikariCP → PostgreSQL (direct / session pooling) |
| Target topology | App → HikariCP → pgagroal (transaction) → PostgreSQL |
| Assessment date | |
| Assessor | |

## Hibernate Connection Handling

```bash
# Run against the application repo
grep -rni "handling_mode\|connection.handling" --include="*.properties" --include="*.yml" .
```

| Setting | Value found | Compatible? |
|---|---|---|
| `hibernate.connection.handling_mode` | _(absent = default, safe)_ | Yes / No |
| `connectionInitSql` / `initSql` | | Yes / No |
| `hibernate.default_schema` | | Yes / No |

## Static Analysis Findings

Complete the [compatibility checklist](java-hibernate-compatibility-checklist.md) and record results here.

| # | Risk area | Result | Notes |
|---|---|---|---|
| 1 | Session-level SET | Pass / Fail / Mitigated | |
| 2 | Temporary tables | Pass / Fail / Mitigated | |
| 3 | Advisory locks | Pass / Fail / Mitigated | |
| 4 | Native SQL | Pass / Fail / Mitigated | |
| 5 | Prepared statements | Pass / Fail / Mitigated | |
| 6 | Batch jobs | Pass / Fail / Mitigated | |
| 7 | Long-running transactions | Pass / Fail / Mitigated | |
| 8 | Connection handling mode | Pass / Fail / Mitigated | |
| 9 | Current pool behavior | Pass / Fail / Mitigated | |
| 10 | LISTEN/NOTIFY | Pass / Fail / Mitigated | |

### Risky Patterns Found

<!--
List every incompatible pattern with file, line, and disposition.
Delete this section if none found.
-->

| File:line | Pattern | Severity | Disposition |
|---|---|---|---|
| | | | |

## Gate Results

| Gate | Description | Result | Evidence |
|---|---|---|---|
| G1 | Static analysis — no incompatible patterns | Pass / Fail | Checklist above |
| G2 | Test suite — zero regressions vs. baseline | Pass / Fail / Skip | |
| G3 | No state leaks — pg_stat_activity clean | Pass / Fail / Skip | |
| G4 | Connection reduction — fewer backend conns | Pass / Fail / Skip | |
| G5 | Error rate — not higher than baseline | Pass / Fail / Skip | |
| G6 | Latency — P50 <5%, P99 <20% increase | Pass / Fail / Skip | |
| G7 | Resilience — recovery after backend restart | Pass / Fail / Skip | |

### G2 Detail: Test Suite

| Metric | Baseline (session) | Transaction mode | Delta |
|---|---|---|---|
| Total tests | | | |
| Passed | | | |
| Failed | | | |
| New failures | | | 0 required |

### G3 Detail: pg_stat_activity

Sampling command used:
```bash
PGPASSWORD=<pw> scripts/sampling/pg-stat-sampler.sh \
  --host <host> --port 5432 --user <user> --db <db> \
  --interval 5 --duration 300 --output <app>-stat-activity.csv
```

- [ ] No SET commands observed between transactions
- [ ] No session-state leakage

### G4 Detail: Connection Count

| Metric | Session mode | Transaction mode |
|---|---|---|
| Peak backend connections | | |
| Average backend connections | | |
| Improvement ratio | | |

### G5 Detail: Error Rate

| Metric | Session mode | Transaction mode |
|---|---|---|
| HTTP 5xx count | | |
| JDBC exceptions | | |
| New exception types | | |

### G6 Detail: Latency

| Percentile | Session mode | Transaction mode | Delta |
|---|---|---|---|
| P50 | | | |
| P95 | | | |
| P99 | | | |

### G7 Detail: Backend Restart

- [ ] Backend restarted during load test
- [ ] Application recovered within 30s
- [ ] No connection leak after recovery

## Evidence Files

| Evidence | Location |
|---|---|
| Compatibility checklist | |
| Baseline test report | |
| Transaction mode test report | |
| pg_stat_activity CSV | |
| Connection count CSV | |
| Latency comparison | |
| Canary metrics (if applicable) | |

## Blockers

<!--
List anything that prevents go. Delete if none.
-->

| # | Blocker | Upstream issue | Remediation |
|---|---|---|---|
| | | | |

## Mitigations Applied

<!--
List any code or config changes made to achieve compatibility. Delete if none.
-->

| # | Change | Risk area | Verification |
|---|---|---|---|
| | | | |

## Recommendation

> Select one:

- [ ] **Compatible** — all gates pass, no blockers, deploy with transaction pooling
- [ ] **Compatible with constraints** — gates pass after mitigations; document constraints below
- [ ] **Not compatible** — blockers exist; continue with session pooling

### Constraints (if applicable)

<!--
e.g. "Must not enable Spring Batch module with transaction pooling"
-->

### Sign-off

| Role | Name | Date |
|---|---|---|
| Assessor | | |
| Reviewer | | |
