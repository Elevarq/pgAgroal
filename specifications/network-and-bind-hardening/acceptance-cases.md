# Acceptance Cases: Network and Bind Hardening

Derived from `spec.md`. Verified by `test/validation/hardened-defaults-test.sh`
(renders the Helm chart with `helm template` and inspects the
`pgexporter.conf.template`).

## AC-01 (normal): default render is an enabled, same-namespace NetworkPolicy

**Spec refs**: NP1, NP2, I1

**Given**: default chart values
**When**: `helm template` renders the chart
**Then**:
- exactly one `kind: NetworkPolicy` is produced
- its ingress contains `- podSelector: {}` (same-namespace allow)
- the pooler port appears in the ingress ports

## AC-02 (boundary): NetworkPolicy can be disabled

**Spec refs**: NP3

**Given**: `networkPolicy.enabled=false`
**When**: the chart is rendered
**Then**: no `kind: NetworkPolicy` appears in the output

## AC-03 (invalid): no same-namespace + no selectors denies all ingress

**Spec refs**: NP4

**Given**: `networkPolicy.allowSameNamespace=false` and no ingress selectors
**When**: the chart is rendered
**Then**: the NetworkPolicy is present but its ingress has no `- podSelector`
or `- namespaceSelector` `from` entry (deny-all ingress)

## AC-04 (functional default): egress is unconstrained by default, opt-in via restrictEgress

**Spec refs**: NP1, NP5, R2

**Given**: default values (`restrictEgress` false)
**When**: the chart is rendered
**Then**: the NetworkPolicy has `policyTypes: [Ingress]` only, no `egress:`
block, and no `cidr: "0.0.0.0/0"` — egress is not constrained, so DNS and
backend connectivity work on any cluster.

**Given**: `restrictEgress=true` (and default `egress.backendCIDRs` empty)
**When**: the chart is rendered
**Then**: `policyTypes` includes `Egress`, and egress contains an `ipBlock`
with `cidr: "0.0.0.0/0"` on the backend port plus the kubeDNS rule. When
`egress.backendCIDRs[0]=10.0.5.10/32` is also set, the render contains
`10.0.5.10/32` and not `0.0.0.0/0`.

## AC-05 (normal): pgexporter binds 0.0.0.0, not the `*` wildcard

**Spec refs**: PEX1

**Given**: the shipped `pgexporter/pgexporter.conf.template`
**When**: its `[pgexporter] host` line is inspected
**Then**: it is `host = 0.0.0.0` and there is no `host = *` line
