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

{{- define "pgagroal.tls.cert.name" -}}
{{- printf "%s-pgagroal-tls-cert" .Release.Name -}}
{{- end -}}

{{- define "pgagroal.tls.key.name" -}}
{{- printf "%s-pgagroal-tls-key" .Release.Name -}}
{{- end -}}

{{- define "pgagroal.tls.ca.name" -}}
{{- printf "%s-pgagroal-tls-ca" .Release.Name -}}
{{- end -}}

{{/*
================================================================================
Reviewed production image — mandatory and immutable (repository@digest only).
================================================================================
*/}}
{{- define "pgagroal.expectedRepository" -}}ghcr.io/elevarq/pgagroal{{- end -}}
{{- define "pgagroal.expectedDigest" -}}sha256:36017745ebd98816c9adac5868965f32b06f72a4049b5fb107cd5bef629fbfcb{{- end -}}
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
{{- if or (lt (int $maxRaw) 1) (gt (int $maxRaw) 10000) -}}
{{- fail "pool.maxConnections must be between 1 and 10000 (pgagroal caps max_connections at 10000)" -}}
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
{{- if and (eq .Values.firewall.internal.inboundAllowType "workload-list") (not .Values.firewall.internal.workloads) -}}
{{- fail "firewall.internal.workloads must be a non-empty list when inboundAllowType is workload-list" -}}
{{- end -}}
{{- /* hbaSource is inserted into a pgagroal HBA line; restrict it to `all` or a
       comma-separated list of CIDRs so it can't inject an auth method (e.g. a
       whitespace/`#` value could comment out the scram-sha-256 method and leave a
       `trust` rule). Each trimmed element must be exactly `all` or d.d.d.d/mask. */ -}}
{{- range $e := splitList "," (.Values.hbaSource | toString) -}}
{{- $t := trim $e -}}
{{- if not (regexMatch "^(all|([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2})$" $t) -}}
{{- fail (printf "hbaSource entry '%s' is invalid; each entry must be `all` or a CIDR (e.g. 10.0.0.0/8). No spaces or other characters are allowed." $t) -}}
{{- end -}}
{{- end -}}
{{- /* Frontend TLS (client -> pooler). Only verify-ca client-cert checking is
       available (the pgagroal 2.1.0 pooler has no tls_cert_auth_mode key). */ -}}
{{- if not (kindIs "bool" .Values.tls.enabled) -}}
{{- fail "tls.enabled must be a boolean (true or false, not a quoted string)" -}}
{{- end -}}
{{- if not (kindIs "bool" .Values.tls.mutualTLS) -}}
{{- fail "tls.mutualTLS must be a boolean (true or false, not a quoted string)" -}}
{{- end -}}
{{- if and .Values.tls.enabled (or (not .Values.tls.cert) (not .Values.tls.key)) -}}
{{- fail "tls.cert and tls.key are required when tls.enabled is true (PEM server certificate and private key)" -}}
{{- end -}}
{{- if and .Values.tls.mutualTLS (not .Values.tls.enabled) -}}
{{- fail "tls.mutualTLS requires tls.enabled=true" -}}
{{- end -}}
{{- if and .Values.tls.mutualTLS (not .Values.tls.caCert) -}}
{{- fail "tls.caCert (PEM CA bundle) is required when tls.mutualTLS is true" -}}
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
