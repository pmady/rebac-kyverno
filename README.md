# ReBAC with Kyverno — Automating Multi-Tenant RBAC at Scale

**KyvernoCon Virtual 2026 — Pavan Madduri**

[![Kyverno](https://img.shields.io/badge/Kyverno-v1.12+-326CE5?style=flat&logo=kubernetes)](https://kyverno.io)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

> Battle-tested and running in production on Amazon EKS.

---

## The Problem

Enterprise Kubernetes environments at scale face a common RBAC problem: every new namespace requires handcrafted Roles and RoleBindings, permissions drift across teams, onboarding takes tickets and cluster-admin intervention, and audit evidence is assembled by hand.

## The Solution

Six Kyverno `generate` ClusterPolicies that automatically scaffold a complete, standardized RBAC structure when any namespace is created — three tiered Roles and their corresponding RoleBindings.

```
 Namespace CREATE event
          │
  ┌───────┴───────┐
  ▼               ▼
3× Role gen   3× RoleBinding gen
  │               │
  ▼               ▼
┌──────────┐ ┌──────────────┐
│ operator │◄│ rb/operator  │  subjects: []
│contributor│◄│rb/contributor│  subjects: []
│  viewer  │◄│ rb/viewer    │  subjects: []
└──────────┘ └──────────────┘
```

### Tiered Access Model

| Role | Verbs | Use Case |
|------|-------|----------|
| **operator** | `*` | Break-glass / SRE |
| **contributor** | `create, get, list, watch, update, patch` | Day-to-day developers |
| **viewer** | `get, list, watch` | Auditors, on-call observers |

## Quick Start

### Prerequisites

- Kubernetes cluster (EKS, GKE, kind, etc.)
- [Kyverno](https://kyverno.io/docs/installation/) v1.12+ installed

### Deploy

```bash
# Install the 6 ReBAC engine policies
kubectl apply -f demo/01-rebac-policies.yaml

# (Optional) Install validation guardrails
kubectl apply -f demo/04-validate-policy.yaml

# Create a tenant namespace — RBAC is auto-scaffolded
kubectl apply -f demo/02-tenant-trigger.yaml

# Verify: 3 Roles + 3 RoleBindings appear instantly
kubectl get role,rolebinding -n tenant-demo
```

### Onboard a User (Self-Service)

```bash
# Add alice as a contributor — no cluster-admin needed
./demo/manage-user-roles.sh add alice@example.com contributor tenant-demo

# Verify
kubectl auth can-i update deployments -n tenant-demo --as=alice@example.com
# → yes

kubectl auth can-i delete pods -n tenant-demo --as=alice@example.com
# → no (contributor has no delete)
```

### Drift Correction

```bash
# Manually add "delete" to viewer role (BAD!)
kubectl apply -f demo/03-drift-test.yaml

# Wait ~10 seconds — Kyverno reverts it
kubectl get role viewer -n tenant-demo -o jsonpath='{.rules[0].verbs}'
# → ["get","list","watch"]  (delete is gone)
```

## Repository Structure

```
├── README.md
└── demo/
    ├── 00-cleanup.sh              # Reset cluster to pre-demo state
    ├── 01-rebac-policies.yaml     # 6 ClusterPolicies (the engine)
    ├── 02-tenant-trigger.yaml     # Namespace that triggers generation
    ├── 03-drift-test.yaml         # Proves synchronize: true reverts edits
    ├── 04-validate-policy.yaml    # Tenant label guardrails
    ├── manage-user-roles.sh       # Self-service user management CLI
    └── RUNBOOK.md                 # Step-by-step live demo commands
```

## Key Design Decisions

### Why `generate`, not `mutate` or Helm?

| Approach | Problem |
|---|---|
| Helm templates | Pull-based, CI per tenant, no self-healing |
| Kyverno `mutate` | Only modifies in-flight objects; can't create siblings |
| Kustomize | Static — drifts on manual edits |
| **Kyverno `generate`** | **Standalone resources, reconciles, survives deletion** |

With `synchronize: true`, the policy is the source of truth — drift auto-heals.

### Two Traps to Avoid

1. **The `nonResourceURLs` trap** — Valid only in `ClusterRole`, never in namespaced `Role`. Kyverno generates it, API server accepts it, RBAC silently ignores it → ghost 403s.

2. **Generate-on-DELETE** — Without a precondition guard, deleting a namespace re-fires the generate rule. The `|| 'BACKGROUND'` fallback is critical for Kyverno's background reconciliation scans.

## Results (Production)

| Metric | Before | After | Delta |
|---|---|---|---|
| Onboarding lead time | ~36 hours | < 30 seconds | 99.98% ↓ |
| Cluster-admin actions/month | ~420 | 0 | 100% eliminated |
| Hand-written RBAC YAML/ns | ~80 lines | 0 | 100% eliminated |
| Permission-drift incidents (90d) | 11 | 0 | 100% resolved |

## Speaker

**Pavan Madduri** — CNCF Golden Kubestronaut & Senior Platform Engineer

- [LinkedIn](https://www.linkedin.com/in/pavanmadduri/)
- [GitHub](https://github.com/pmady)
- [Google Scholar](https://scholar.google.com/citations?hl=en&user=au0O-8oAAAAJ)

## License

Apache License 2.0
