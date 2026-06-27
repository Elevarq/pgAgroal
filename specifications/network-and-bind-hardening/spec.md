# Specification: Network and Bind Hardening

## Status

ACTIVE (#49; v1.4.0 hardened defaults)

## Purpose

Reduce the network blast radius of the pgagroal pooler and the pgexporter
metrics endpoint by hardening their shipped defaults:

- The Helm chart's `NetworkPolicy` is **enabled by default** and admits only
  same-namespace pods to the pooler, denying ingress from other namespaces,
  while keeping the default render reachable in-namespace.
- The pgexporter metrics listener binds the IPv4 wildcard (`0.0.0.0`) rather
  than the `*` wildcard, with exposure bounded at the network layer.

These complement the HBA source-address restriction
(`specifications/hba-source-restriction/`). The `pgagroal.host: "*"` bind is
intentionally retained (the pooler must bind the pod IP to be reachable via
the Service); exposure is constrained by HBA + NetworkPolicy, not by the bind.

## Interfaces

### Inputs (Helm values)

| Input | Type | Default | Constraints |
|-------|------|---------|-------------|
| `networkPolicy.enabled` | bool | `true` | When false, no NetworkPolicy is rendered. |
| `networkPolicy.allowSameNamespace` | bool | `true` | When true, all pods in the release namespace may reach the pooler. |
| `networkPolicy.ingressPodSelectors` | list(map) | `[]` | Additional pods admitted, by label map. |
| `networkPolicy.ingressNamespaceSelectors` | list(map) | `[]` | Namespaces admitted, by label map. |
| `networkPolicy.restrictEgress` | bool | `false` | When false, the policy governs ingress only (egress unconstrained). When true, `policyTypes` adds `Egress` and the egress rules below apply. |
| `networkPolicy.egress.backendCIDRs` | list(string) | `[]` | (restrictEgress only) Backend Postgres CIDRs. Empty => backend port on `0.0.0.0/0`. |
| `networkPolicy.egress.kubeDNS` | list(string) | `["10.96.0.10/32"]` | (restrictEgress only) DNS resolver CIDRs. MUST match the cluster (EKS = `10.100.0.10/32`). |

### Inputs (pgexporter)

| Input | Type | Default | Constraints |
|-------|------|---------|-------------|
| `pgexporter.conf.template` `[pgexporter] host` | string | `0.0.0.0` | The metrics listener bind address. |

## Behaviors

- **NP1** — Given default values, when the chart is rendered, then exactly one
  `NetworkPolicy` is produced with `policyTypes: [Ingress]` only (egress is not
  constrained by default — see NP5). Given `restrictEgress: true`, the same
  render adds `Egress` to `policyTypes`.
- **NP2** — Given default values (`allowSameNamespace: true`), when the chart
  is rendered, then the ingress rule includes an empty `podSelector: {}` (the
  same-namespace allow) and the pooler port, so the pooler is reachable from
  same-namespace pods.
- **NP3** — Given `networkPolicy.enabled: false`, when the chart is rendered,
  then no `NetworkPolicy` is produced.
- **NP4** — Given `allowSameNamespace: false` and no ingress selectors, when
  the chart is rendered, then the ingress has no `from` rule (all ingress
  denied — conservative fallback, not an unreachable accident of the default).
- **NP5** — Given `restrictEgress: false` (default), when the chart is
  rendered, then NO `egress` rule and no `Egress` policyType are produced —
  egress is unconstrained, so DNS resolution and backend connectivity work on
  any cluster. Given `restrictEgress: true` with `egress.backendCIDRs` empty,
  egress to the backend port is allowed to `0.0.0.0/0` (port-restricted) plus
  the `kubeDNS` CIDR(s); given `backendCIDRs` set, backend egress is restricted
  to those CIDRs.
- **PEX1** — The pgexporter metrics listener binds `0.0.0.0` (IPv4 wildcard),
  never the `*` wildcard and never a loopback address (which would make the
  cross-boundary scrape unreachable).

## Rules

- **R1** — The default-rendered ingress admits same-namespace pods and denies
  pods in other namespaces unless an explicit
  `ingressNamespaceSelectors` / `ingressPodSelectors` entry admits them.
- **R2** — Egress is constrained only when `restrictEgress: true`; then it is
  limited to the backend Postgres port and DNS, and no other egress is
  permitted. When false, the policy does not restrict egress at all.

## Invariants

- **I1** — The default chart render is reachable in-namespace: the
  NetworkPolicy never makes the pooler unreachable by same-namespace clients
  under default values.
- **I2** — Enabling the NetworkPolicy never opens ingress from outside the
  namespace except via an explicit operator selector.

## Failure conditions

| Trigger | Response |
|---------|----------|
| `networkPolicy.allowSameNamespace: false` with no ingress selectors | No ingress rule rendered (deny-all ingress); install NOTES warn. |
| `restrictEgress: true` with `egress.backendCIDRs` empty | Backend egress allowed on `0.0.0.0/0` (port-restricted); install NOTES recommend tightening. |
| `restrictEgress: true` with `egress.kubeDNS` not matching the cluster resolver | DNS egress denied → backend hostname resolution fails. Operator MUST set kubeDNS to the cluster resolver (EKS `10.100.0.10/32`). This breakage risk is why egress containment is opt-in, not default-on. |

## Constraints / NFR

- The NetworkPolicy is a no-op on clusters whose CNI does not enforce it;
  this is acceptable and the value remains default-on for clusters that do.
- pgexporter exposure is additionally bounded by the docker-compose loopback
  publish (`127.0.0.1:5002`); the bind alone is not the only control.
