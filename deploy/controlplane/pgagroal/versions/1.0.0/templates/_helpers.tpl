{{/*
================================================================================
Resource naming — all names derive from .Release.Name to avoid collisions.
================================================================================
*/}}
{{- define "pgagroal.name" -}}
{{- printf "%s-pgagroal" .Release.Name -}}
{{- end -}}

{{- define "pgagroal.identity.name" -}}
{{- printf "%s-pgagroal-identity" .Release.Name -}}
{{- end -}}

{{- define "pgagroal.policy.name" -}}
{{- printf "%s-pgagroal-policy" .Release.Name -}}
{{- end -}}

{{- define "pgagroal.credentials.name" -}}
{{- printf "%s-pgagroal-credentials" .Release.Name -}}
{{- end -}}

{{/*
================================================================================
Reviewed production image — mandatory and immutable (repository@digest only).
================================================================================
*/}}
{{- define "pgagroal.expectedRepository" -}}ghcr.io/elevarq/pgagroal{{- end -}}
{{- define "pgagroal.expectedDigest" -}}sha256:749e3afc534af0c51dec128c7b229f8126d1cabdbea530d68e0ba9bf22a45928{{- end -}}
{{- define "pgagroal.image" -}}
{{- printf "%s@%s" (include "pgagroal.expectedRepository" .) (include "pgagroal.expectedDigest" .) -}}
{{- end -}}

{{/*
================================================================================
Validation — fail fast on missing/invalid inputs before any resource renders.
================================================================================
*/}}
{{- define "pgagroal.validateConfig" -}}
{{- if ne .Values.image.repository (include "pgagroal.expectedRepository" .) -}}
{{- fail (printf "image.repository must remain %s; the reviewed production image is used unchanged" (include "pgagroal.expectedRepository" .)) -}}
{{- end -}}
{{- if ne .Values.image.digest (include "pgagroal.expectedDigest" .) -}}
{{- fail (printf "image.digest must remain %s; mutable tags and unreviewed digests are not allowed" (include "pgagroal.expectedDigest" .)) -}}
{{- end -}}
{{- if not .Values.backend.host -}}
{{- fail "backend.host is required (the PostgreSQL host pgAgroal pools to, reachable from the GVC)" -}}
{{- end -}}
{{- if not .Values.auth.username -}}
{{- fail "auth.username is required (a valid backend PostgreSQL user)" -}}
{{- end -}}
{{- if not .Values.auth.password -}}
{{- fail "auth.password is required (stored in a Control Plane secret)" -}}
{{- end -}}
{{- if not .Values.hbaSource -}}
{{- fail "hbaSource is required (comma-separated CIDRs or \"all\")" -}}
{{- end -}}
{{- if not (kindIs "bool" .Values.metrics.enabled) -}}
{{- fail "metrics.enabled must be a boolean (true or false, not a quoted string)" -}}
{{- end -}}
{{- $logLevels := list "fatal" "error" "warn" "info" "debug1" "debug2" "debug3" "debug4" "debug5" "trace" -}}
{{- if not (has .Values.logLevel $logLevels) -}}
{{- fail (printf "logLevel '%s' is invalid; use one of: %s" .Values.logLevel (join ", " $logLevels)) -}}
{{- end -}}
{{- /* Integer-shape checks before int coercion (Sprig int silently coerces bools/floats). */ -}}
{{- $portRaw := .Values.backend.port | toString -}}
{{- if not (regexMatch "^[0-9]+$" $portRaw) -}}
{{- fail "backend.port must be an integer between 1 and 65535" -}}
{{- end -}}
{{- if or (lt (int $portRaw) 1) (gt (int $portRaw) 65535) -}}
{{- fail "backend.port must be between 1 and 65535" -}}
{{- end -}}
{{- $maxRaw := .Values.pool.maxConnections | toString -}}
{{- if not (regexMatch "^[0-9]+$" $maxRaw) -}}
{{- fail "pool.maxConnections must be a positive integer" -}}
{{- end -}}
{{- if lt (int $maxRaw) 1 -}}
{{- fail "pool.maxConnections must be at least 1" -}}
{{- end -}}
{{- $replicasRaw := .Values.replicas | toString -}}
{{- if not (regexMatch "^[0-9]+$" $replicasRaw) -}}
{{- fail "replicas must be a positive integer" -}}
{{- end -}}
{{- if lt (int $replicasRaw) 1 -}}
{{- fail "replicas must be at least 1" -}}
{{- end -}}
{{- $inboundTypes := list "none" "same-gvc" "same-org" "workload-list" -}}
{{- if not (has .Values.firewall.internal.inboundAllowType $inboundTypes) -}}
{{- fail (printf "firewall.internal.inboundAllowType must be one of: %s" (join ", " $inboundTypes)) -}}
{{- end -}}
{{- end -}}

{{/*
================================================================================
Labeling — delegate to the shared cpln-common library.
================================================================================
*/}}
{{- define "pgagroal.tags" -}}
{{- include "cpln-common.tags" . -}}
{{- end -}}
