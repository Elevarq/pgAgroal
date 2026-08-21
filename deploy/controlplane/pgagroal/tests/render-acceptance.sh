#!/usr/bin/env bash
# Acceptance tests for the pgAgroal Control Plane Catalog template.
#
# Traceability (spec rule -> case). Mirrors the upstream validate-charts.yml gate
# plus this template's fail-fast contract (versions/1.0.0/templates/_helpers.tpl):
#
#   PGA-R001  chart renders with DEFAULT values + a dummy GVC (upstream CI parity)
#   PGA-R002  rendered output carries the required cpln/marketplace* tags
#   PGA-R003  Chart.yaml description is <= 15 words
#   PGA-R004  workload image is the exact reviewed repository@digest
#   PGA-R005  image.repository / image.digest cannot be changed
#   PGA-R006  required inputs (backend.host/auth.username/auth.password/hbaSource) fail-fast when empty
#   PGA-R007  logLevel enum; firewall.inboundAllowType enum; metrics.enabled boolean
#   PGA-R008  integer-shape: backend.port (1..65535), pool.maxConnections (1..10000), replicas (>=1)
#   PGA-R009  workload is stateless (no volumeset), pooler port 6432/tcp, egress scoped to backend port
#   PGA-R010  security invariants: unknown-user passthrough off, pgagroal-cli ping probe, metrics off by default
#   PGA-R011  hbaSource accepts only `all` or CIDRs (no HBA injection); workload-list non-empty
set -uo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/versions/1.0.0"
EXPECTED_DIGEST="sha256:749e3afc534af0c51dec128c7b229f8126d1cabdbea530d68e0ba9bf22a45928"
fails=0

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }
render() { helm template validation "$CHART_DIR" --set global.cpln.gvc=validation-gvc "$@" 2>&1; }

echo "== deps =="
helm dependency build "$CHART_DIR" >/dev/null 2>&1 || { echo "helm dependency build failed"; exit 1; }

echo "== positive (R001..R004, R009) =="
if OUT="$(render)"; then
  pass "R001 renders with defaults + dummy gvc"
  for t in 'cpln/marketplace: "true"' 'cpln/marketplace-template:' 'cpln/marketplace-template-version:' 'cpln/marketplace-gvc:'; do
    if echo "$OUT" | grep -q "$t"; then pass "R002 tag present: $t"; else fail "R002 tag missing: $t"; fi
  done
  if echo "$OUT" | grep -qE "image: ghcr.io/elevarq/pgagroal@${EXPECTED_DIGEST}\b"; then
    pass "R004 image is reviewed repository@digest"
  else
    fail "R004 image not digest-pinned to the reviewed digest"
  fi
  if echo "$OUT" | grep -q 'kind: volumeset'; then
    fail "R009 unexpected volumeset (pooler is stateless)"
  else
    pass "R009 stateless (no volumeset)"
  fi
  if echo "$OUT" | grep -B1 'protocol: tcp' | grep -q 'number: 6432'; then
    pass "R009 pooler port 6432/tcp exposed"
  else
    fail "R009 pooler port 6432/tcp missing"
  fi
  EGRESS="$(echo "$OUT" | grep -A2 'outboundAllowPort:')"
  if echo "$EGRESS" | grep -qE 'number: 5432' && echo "$EGRESS" | grep -qE 'protocol: tcp'; then
    pass "R009 egress scoped to backend port (tcp/5432)"
  else
    fail "R009 egress not scoped to the backend port"
  fi
  # R010 — security-critical rendered invariants.
  if echo "$OUT" | grep -A1 'PGAGROAL_ALLOW_UNKNOWN_USERS' | grep -q 'value: "false"'; then
    pass "R010 unknown-user passthrough disabled"
  else
    fail "R010 PGAGROAL_ALLOW_UNKNOWN_USERS is not \"false\""
  fi
  if echo "$OUT" | grep -q 'pgagroal-cli' && echo "$OUT" | grep -q 'ping'; then
    pass "R010 pgagroal-cli ping exec probe present"
  else
    fail "R010 pgagroal-cli ping exec probe missing"
  fi
  if echo "$OUT" | grep -q 'number: 2346'; then
    fail "R010 metrics port 2346 exposed by default (should be off)"
  else
    pass "R010 metrics port absent by default"
  fi
else
  fail "R001 default render failed:"; echo "$OUT" | tail -3
fi

DESC="$(sed -n 's/^description:[[:space:]]*//p' "$CHART_DIR/Chart.yaml" | head -1)"
WORDS="$(echo "$DESC" | tr ' ' '\n' | grep -cvE '^$|^(—|–|-)$')"
if [ "$WORDS" -le 15 ]; then pass "R003 description is $WORDS words (<=15)"; else fail "R003 description is $WORDS words (>15)"; fi

echo "== negative (each MUST fail to render) =="
neg() { local rule="$1" label="$2"; shift 2
  if render "$@" >/dev/null 2>&1; then fail "$rule rendered but should have failed: $label"; else pass "$rule rejects $label"; fi
}
neg R005 "changed image.repository"  --set image.repository=evil/pgagroal
neg R005 "changed image.digest"      --set image.digest=sha256:dead
neg R006 "empty backend.host"        --set-string backend.host=
neg R006 "empty auth.username"       --set-string auth.username=
neg R006 "empty auth.password"       --set-string auth.password=
neg R006 "empty hbaSource"           --set-string hbaSource=
neg R007 "bad logLevel"              --set logLevel=verbose
neg R007 "bad inboundAllowType"      --set firewall.internal.inboundAllowType=public
neg R007 "string metrics.enabled"    --set-string metrics.enabled=false
neg R008 "backend.port < 1"          --set backend.port=0
neg R008 "backend.port > 65535"      --set backend.port=70000
neg R008 "boolean backend.port"      --set backend.port=true
neg R008 "fractional backend.port"   --set-json backend.port=5432.5
neg R008 "maxConnections < 1"        --set pool.maxConnections=0
neg R008 "fractional maxConnections" --set-json pool.maxConnections=1.5
neg R008 "replicas < 1"              --set replicas=0
neg R008 "boolean replicas"          --set replicas=true
neg R008 "maxConnections > 10000"    --set pool.maxConnections=20000
neg R011 "hbaSource injects trust"   --set-string hbaSource="all trust #"
neg R011 "hbaSource with space"      --set-string hbaSource="10.0.0.0/8 trust"
neg R011 "hbaSource bogus token"     --set-string hbaSource="not-a-cidr"
neg R011 "workload-list empty"       --set firewall.internal.inboundAllowType=workload-list

echo "== positive opt-ins (must render) =="
if render --set metrics.enabled=true 2>/dev/null | grep -q 'number: 2346'; then
  pass "R007 metrics.enabled=true exposes the metrics port 2346"
else
  fail "R007 metrics.enabled=true did not expose port 2346"
fi
if render --set backend.port=6432 2>/dev/null | grep -A2 'outboundAllowPort:' | grep -q 'number: 6432'; then
  pass "R008 overridden backend.port propagates to outboundAllowPort"
else
  fail "R008 overridden backend.port not reflected in outboundAllowPort"
fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILED"; exit 1; fi
