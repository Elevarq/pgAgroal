# Specification: Java/Hibernate Transaction Pooling Compatibility Validation

Status: ACTIVE

## Objective

Determine, with evidence, whether each of three Java/Hibernate applications
can safely operate through pgagroal in transaction pooling mode (`pipeline =
transaction`) without behavioral regressions, data corruption, or
performance degradation.

Produce a per-application **go / no-go** decision with supporting evidence.

## Scope

This validation covers **the interaction between the application's JDBC
connection usage patterns and pgagroal's transaction pooling semantics**.

In scope:
- Session-level PostgreSQL state that does not survive connection reassignment
- Hibernate connection management and release strategies
- Application SQL patterns incompatible with connection multiplexing
- Performance under transaction pooling vs. session pooling vs. direct

Out of scope:
- pgagroal daemon stability (covered by separate operational tests)
- PostgreSQL backend correctness
- Application business logic correctness unrelated to connection behavior
- Network/TLS configuration

## Background: Transaction Pooling Semantics

In transaction pooling mode, pgagroal assigns a backend connection to a
client **only for the duration of a transaction**. Between transactions, the
backend connection is returned to the pool and may be assigned to a different
client.

This means **any state set on the backend connection outside a transaction
is lost** when the connection is returned. This includes:

- `SET` commands (search_path, statement_timeout, work_mem, etc.)
- Temporary tables (created outside a transaction or with ON COMMIT DROP)
- Advisory locks
- Prepared statements (server-side, named)
- `LISTEN`/`NOTIFY` registrations
- Cursors (WITH HOLD)
- Session-level sequences (`lastval()` across transactions)

## Assumptions

1. Applications use Spring Boot + Hibernate (JPA) with HikariCP as the
   application-side connection pool.
2. Applications connect to PostgreSQL via JDBC (postgresql driver).
3. Applications use `@Transactional` annotations or programmatic transaction
   management.
4. The pgagroal container is deployed per the existing Helm chart with
   `pipeline = transaction` (requires enabling `track_prepared_statements`).
5. Each application has an existing test suite that can be run against a
   pgagroal-proxied database.
6. A staging/lab environment is available that mirrors production topology.

## Application Risk Areas

Each application must be assessed against these risk categories:

### R1: Session-level SET statements

Hibernate and Spring may issue `SET` commands on connection checkout:
- `SET search_path` (multi-tenant schemas)
- `SET statement_timeout` (query guards)
- `SET application_name` (observability)
- Custom `SET` via `hibernate.connection.provider_disables_autocommit` or
  `ConnectionCustomizer`

**Risk**: state set before a transaction is lost when the connection is
returned. State set inside a transaction is also lost after commit/rollback.

**Detection**: grep application code + Hibernate config for SET usage;
monitor `pg_stat_activity.query` for SET commands.

### R2: Temporary tables

`CREATE TEMP TABLE` creates a table that exists for the session lifetime.
In transaction pooling, the session boundary is the transaction boundary.

**Risk**: temp tables created in one transaction are invisible in the next
(different backend connection).

**Detection**: grep for `CREATE TEMP`, `CREATE TEMPORARY`, Hibernate
`@Table` with temp strategies.

### R3: Advisory locks

`pg_advisory_lock()` and `pg_try_advisory_lock()` are session-level.
They are released when the session ends, which in transaction pooling is
at commit/rollback.

`pg_advisory_xact_lock()` is transaction-scoped and is safe.

**Risk**: session-level advisory locks silently release at transaction end.

**Detection**: grep for `advisory_lock` (without `xact`).

### R4: Native SQL and prepared statements

Hibernate may use server-side prepared statements. pgagroal's
`track_prepared_statements` setting handles this, but only for simple cases.

Native SQL (`@Query(nativeQuery=true)`, `createNativeQuery()`) may contain
patterns incompatible with connection multiplexing.

**Risk**: stale prepared statement references after connection reassignment.

**Detection**: grep for `nativeQuery`, `createNativeQuery`,
`PreparedStatement`; check `hibernate.jdbc.batch_size` settings.

### R5: Batch jobs and long-running transactions

Batch processing jobs (Spring Batch, `@Scheduled`) may hold connections
for extended periods or assume connection affinity across multiple
operations.

**Risk**: long-held connections reduce pool effectiveness; jobs that span
multiple transactions lose state between them.

**Detection**: review batch job code for multi-transaction patterns.

### R6: Connection handling mode

Hibernate's `hibernate.connection.handling_mode` controls when connections
are acquired and released:

- `DELAYED_ACQUISITION_AND_RELEASE_BEFORE_TRANSACTION_COMPLETION` — safe
  for transaction pooling (releases connection at transaction end)
- `DELAYED_ACQUISITION_AND_RELEASE_AFTER_TRANSACTION` — safe
- `DELAYED_ACQUISITION_AND_HOLD` — **unsafe** (holds across transactions)

Spring Boot 3.x defaults to release-after-transaction, which is compatible.

**Detection**: check `application.properties` / `application.yml` for
`hibernate.connection.handling_mode`; check for `@Transactional` coverage.

### R7: HikariCP interaction

The application already has HikariCP as its connection pool. With pgagroal
in front, there are two pools in series:

- HikariCP → pgagroal → PostgreSQL

**Risk**: HikariCP's connection validation (`SELECT 1`) runs outside a
transaction. In transaction pooling mode, this validation runs on a
connection that may be reassigned before the next real query.

**Mitigation**: this is generally safe because HikariCP acquires a fresh
pgagroal connection per checkout, but connection test queries add overhead.

## Preconditions

Before validation begins:

| # | Precondition |
|---|---|
| P1 | Lab environment available with pgagroal in `pipeline = transaction` mode |
| P2 | Application source code accessible for static analysis |
| P3 | Application test suite runnable against lab environment |
| P4 | `pg_stat_activity` and `pg_stat_statements` accessible on the backend |
| P5 | Baseline metrics from session pooling mode (or direct connection) available |
| P6 | `track_prepared_statements = on` set in pgagroal config |

## Pass/Fail Criteria

An application **passes** transaction pooling validation when ALL of:

1. Static analysis finds no incompatible patterns (R1-R7), OR all found
   patterns have documented mitigations that have been applied.
2. The application's existing test suite passes at 100% against pgagroal
   in transaction mode (no regressions from baseline).
3. A workload replay (or realistic load test) shows no increase in error
   rate compared to session pooling baseline.
4. Backend connection count under load is measurably lower than with
   session pooling (the whole point of transaction pooling).
5. No transaction-scoped state leaks are detected in `pg_stat_activity`
   monitoring during the test.

An application **fails** (no-go) when ANY of:

1. Static analysis finds incompatible patterns that cannot be mitigated
   without application code changes.
2. Test suite failures appear that do not exist in session pooling mode.
3. Error rate under load is higher than session pooling baseline.
4. Data corruption or incorrect results are observed.

## Rollback Criteria

If an application fails validation:

- Do NOT deploy it with transaction pooling.
- Continue using `pipeline = session` (current default) or `pipeline = auto`.
- Document the specific incompatibility for the development team.
- Re-validate after the incompatibility is resolved in application code.

Transaction pooling can be enabled per-deployment. A mixed estate is valid:
compatible apps use transaction mode, incompatible apps use session mode.

## Outputs

For each application, produce:

1. Static analysis report (checklist with evidence)
2. Test suite results (pass/fail count, diff from baseline)
3. Load test comparison (session vs. transaction: latency, error rate,
   connection count)
4. Go/no-go recommendation with justification
