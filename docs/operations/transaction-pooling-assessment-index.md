# Transaction Pooling Assessment Index

Summary of per-application transaction pooling compatibility assessments.

This index is a rollup view. Each row links to a detailed assessment file
produced from the [assessment template](transaction-pooling-app-assessment-template.md).
Update this index whenever a per-app assessment is created or changes status.

## Assessment Overview

| Application | Owner | Current topology | Handling mode | Key risks found | G1 | G2 | G3 | G4 | G5 | G6 | G7 | Recommendation | Priority | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| *(example)* | *(team)* | *HikariCP → PG direct* | *default (safe)* | *none* | *Pass* | *Pass* | *Pass* | *Pass* | *Pass* | *Pass* | *Pass* | *Compatible* | *1* | *[assessment](assessment-example.md)* |
| App 1 | | | | | | | | | | | | | | |
| App 2 | | | | | | | | | | | | | | |
| App 3 | | | | | | | | | | | | | | |

### Column reference

| Column | Values | Source |
|---|---|---|
| G1 | Pass / Fail | Static analysis (checklist items 1-10) |
| G2 | Pass / Fail / Pending | Test suite — zero regressions vs. baseline |
| G3 | Pass / Fail / Pending | pg_stat_activity — no state leaks |
| G4 | Pass / Fail / Pending | Connection count — fewer backend connections |
| G5 | Pass / Fail / Pending | Error rate — not higher than baseline |
| G6 | Pass / Fail / Pending | Latency — P50 <5%, P99 <20% increase |
| G7 | Pass / Fail / Pending | Resilience — recovery after backend restart |
| Recommendation | Compatible / Constrained / Not compatible | Final assessment sign-off |
| Priority | 1 (first) / 2 / 3 / Hold | Rollout order; Hold = blocked |

## Rollout Order

| Priority | Application | Rationale |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |

## Blockers Across Applications

<!--
Consolidate blockers from all assessments here. Remove when resolved.
-->

| Application | Blocker | Upstream issue | Status |
|---|---|---|---|
| | | | |

## How to maintain

1. When starting an assessment, add the application row with gates set to `Pending`.
2. As gates complete, update each cell to `Pass` or `Fail`.
3. When the assessment is signed off, set the Recommendation and Priority.
4. Link the detailed assessment file in the Notes column.
5. If an assessment changes (e.g. after a mitigation), update both the detailed file and this index.
