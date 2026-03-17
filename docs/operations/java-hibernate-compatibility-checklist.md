# Java/Hibernate Transaction Pooling Compatibility Checklist

Per-application checklist. Complete once per application before enabling
`pipeline = transaction` in pgagroal.

## Application: ____________________

### 1. Session-level SET statements

```bash
# Search for SET commands in application code
grep -rn "SET " --include="*.java" --include="*.xml" --include="*.sql" src/
grep -rn "search_path\|statement_timeout\|work_mem\|application_name" --include="*.java" --include="*.properties" --include="*.yml" src/ config/
```

- [ ] No SET statements found outside `@Transactional` methods
- [ ] No `hibernate.default_schema` with schema switching
- [ ] No connection init hooks (`ConnectionCustomizer`, `initSql`, HikariCP `connectionInitSql`)

Finding: ___ Compatible / Incompatible / Needs mitigation

### 2. Temporary tables

```bash
grep -rni "CREATE TEMP\|CREATE TEMPORARY\|TEMP TABLE" --include="*.java" --include="*.sql" src/
grep -rni "TemporaryTable\|@Table.*temp" --include="*.java" src/
```

- [ ] No temporary tables, OR
- [ ] All temp tables use `ON COMMIT DROP` inside explicit transactions

Finding: ___

### 3. Advisory locks

```bash
grep -rni "advisory_lock\|advisory_xact_lock" --include="*.java" --include="*.sql" src/
```

- [ ] No advisory locks, OR
- [ ] Only `pg_advisory_xact_lock()` (transaction-scoped, safe)

Finding: ___

### 4. Native SQL

```bash
grep -rni "nativeQuery\|createNativeQuery\|createSQLQuery" --include="*.java" src/
```

Review each native query for:
- [ ] No session-state assumptions (SET, temp tables, lastval)
- [ ] No `DEALLOCATE` or explicit `PREPARE` statements

Finding: ___

### 5. Prepared statements

```bash
# Check Hibernate batch settings
grep -rni "jdbc.batch_size\|order_inserts\|order_updates" --include="*.properties" --include="*.yml" config/ src/
```

- [ ] `track_prepared_statements = on` is configured in pgagroal
- [ ] Batch operations use `@Transactional` (prepared statements are within a transaction)

Finding: ___

### 6. Batch jobs

```bash
grep -rni "@Scheduled\|@EnableScheduling\|Spring Batch\|JobLauncher\|StepBuilder" --include="*.java" src/
```

- [ ] No batch jobs, OR
- [ ] Each batch step is independently transactional
- [ ] No state carried between steps (no temp tables, no session vars)

Finding: ___

### 7. Long-running transactions

```bash
# Check for explicit transaction timeouts
grep -rni "timeout.*=\|@Transactional.*timeout" --include="*.java" src/
```

- [ ] No transactions expected to exceed 30s (blocking_timeout)
- [ ] Long operations are chunked into separate transactions

Finding: ___

### 8. Connection handling mode

```bash
grep -rni "handling_mode\|connection.handling" --include="*.properties" --include="*.yml" config/ src/
```

- [ ] Not set (Spring Boot default is safe), OR
- [ ] Set to `DELAYED_ACQUISITION_AND_RELEASE_AFTER_TRANSACTION` (safe)
- [ ] NOT set to `DELAYED_ACQUISITION_AND_HOLD` (unsafe)

Finding: ___

### 9. Current connection pool behavior

```bash
# Check HikariCP settings
grep -rni "hikari\|maximumPoolSize\|minimumIdle\|connectionTestQuery\|connectionTimeout" --include="*.properties" --include="*.yml" config/ src/
```

- [ ] `maximumPoolSize` documented: ___
- [ ] `connectionTestQuery` documented (or default validation): ___
- [ ] No custom `ConnectionCustomizer` or init hooks

Finding: ___

### 10. LISTEN/NOTIFY

```bash
grep -rni "LISTEN\|NOTIFY\|pg_notify" --include="*.java" --include="*.sql" src/
```

- [ ] No LISTEN/NOTIFY (incompatible with transaction pooling)

Finding: ___

---

## Summary

| Check | Result | Notes |
|---|---|---|
| 1. SET statements | | |
| 2. Temp tables | | |
| 3. Advisory locks | | |
| 4. Native SQL | | |
| 5. Prepared statements | | |
| 6. Batch jobs | | |
| 7. Long transactions | | |
| 8. Handling mode | | |
| 9. Pool behavior | | |
| 10. LISTEN/NOTIFY | | |

**Decision**: Go / No-Go / Conditional (with mitigations)

**Reviewer**: _____________________ **Date**: ___________
