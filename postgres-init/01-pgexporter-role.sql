-- Least-privilege monitoring role for pgexporter.
--
-- pgexporter connects DIRECTLY to PostgreSQL (never through pgagroal) using a
-- role granted pg_monitor, not a superuser. This models the recommended
-- monitoring posture: the exporter can read the statistics views it needs and
-- nothing more.
--
-- Example credentials only. Real deployments inject the password at runtime.

CREATE ROLE pgexporter WITH LOGIN PASSWORD 'pgexporter';
GRANT pg_monitor TO pgexporter;
