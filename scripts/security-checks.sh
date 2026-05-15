#!/usr/bin/env bash
# Local security gate for the pgAgroal container and Helm chart.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

step() { printf '\033[1;34m[security]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[security]\033[0m PASS %s\n' "$*"; }
fail() { printf '\033[1;31m[security]\033[0m FAIL %s\n' "$*" >&2; }

require_cmd() {
  local cmd="$1" hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "missing required tool: $cmd"
    printf 'Install locally with: %s\n' "$hint" >&2
    return 127
  fi
}

render_chart() {
  local output="$1"
  helm template pgagroal helm/pgagroal \
    --set credentials.username=testuser \
    --set credentials.password=testpass \
    --set postgresql.host=pg-host > "$output"
}

run_secrets() {
  require_cmd gitleaks "brew install gitleaks" || return $?
  step "gitleaks protect --staged"
  gitleaks protect --source . --redact --no-banner --staged
  step "gitleaks detect current commit"
  gitleaks detect --source . --redact --no-banner --log-opts="-1"
  ok "secrets"
}

run_static() {
  require_cmd semgrep "brew install semgrep" || return $?
  step "semgrep shell/Docker/YAML security rules"
  semgrep scan --config p/security-audit --config p/secrets .
  ok "static"
}

run_helm() {
  require_cmd helm "brew install helm" || return $?
  step "helm lint helm/pgagroal"
  helm lint helm/pgagroal
  step "helm template"
  render_chart /tmp/pgagroal-rendered.yaml
  ok "helm"
}

run_policy() {
  require_cmd helm "brew install helm" || return $?
  require_cmd kube-linter "brew install kube-linter" || return $?
  step "kube-linter rendered Helm output"
  render_chart /tmp/pgagroal-rendered.yaml
  kube-linter lint /tmp/pgagroal-rendered.yaml
  ok "policy"
}

run_sbom() {
  require_cmd syft "brew install syft" || return $?
  mkdir -p .security/cache
  step "syft dir:. -> .security/sbom.spdx.json"
  SYFT_CHECK_FOR_APP_UPDATE=false XDG_CACHE_HOME="$REPO_ROOT/.security/cache" \
    syft dir:. --source-name "$(basename "$REPO_ROOT")" --source-version local \
      -o spdx-json > .security/sbom.spdx.json
  ok "sbom"
}

run_artifact_vulns() {
  require_cmd grype "brew install grype" || return $?
  if [[ ! -s .security/sbom.spdx.json ]]; then
    run_sbom
  fi
  step "grype .security/sbom.spdx.json"
  grype sbom:.security/sbom.spdx.json
  ok "artifact-vulns"
}

run_all() {
  run_secrets
  run_static
  run_helm
  run_policy
  run_sbom
  run_artifact_vulns
}

case "${1:-all}" in
  secrets) run_secrets ;;
  static) run_static ;;
  helm) run_helm ;;
  policy) run_policy ;;
  sbom) run_sbom ;;
  artifact-vulns) run_artifact_vulns ;;
  all) run_all ;;
  *)
    printf 'usage: %s [secrets|static|helm|policy|sbom|artifact-vulns|all]\n' "$0" >&2
    exit 2
    ;;
esac
