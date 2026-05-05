# KyvernoCon 2026 Live Demo Runbook

**Talk:** ReBAC with Kyverno — Automating Multi-Tenant RBAC at Scale
**Speaker:** Pavan Madduri
**Duration:** ~3 minutes of the 20-minute slot (slides 6)

---

## Pre-Demo Checklist

```bash
# Confirm cluster access
kubectl cluster-info

# Confirm Kyverno is running
kubectl get pods -n kyverno

# Clean any leftover state
./00-cleanup.sh

# Verify clean slate
kubectl get clusterpolicy | grep generate
# → (no results)
kubectl get ns tenant-demo 2>&1
# → Error from server (NotFound)
```

---

## Demo Script (copy-paste ready)

### Step 1 — Install the 6 ReBAC engine policies

```bash
kubectl apply -f 01-rebac-policies.yaml
```

**Say:** *"Six ClusterPolicies — three generate Roles, three generate RoleBindings. That's the entire engine."*

**Verify:**
```bash
kubectl get clusterpolicy
```
Expected: 6 policies in `Ready` state.

---

### Step 2 — Create a tenant namespace (triggers generation)

```bash
kubectl apply -f 02-tenant-trigger.yaml
```

**Say:** *"I create one namespace. Kyverno does the rest."*

---

### Step 3 — Show auto-generated RBAC resources

```bash
kubectl get role,rolebinding -n tenant-demo
```

**Expected output:**
```
NAME                                       CREATED AT
role.rbac.authorization.k8s.io/operator    ...
role.rbac.authorization.k8s.io/contributor ...
role.rbac.authorization.k8s.io/viewer      ...

NAME                                              ROLE              ...
rolebinding.rbac.authorization.k8s.io/operator    Role/operator     ...
rolebinding.rbac.authorization.k8s.io/contributor Role/contributor  ...
rolebinding.rbac.authorization.k8s.io/viewer      Role/viewer       ...
```

**Say:** *"Six resources appeared — three Roles and three RoleBindings. We didn't write a single line of RBAC YAML."*

---

### Step 4 — Self-service: add a user

```bash
kubectl patch rolebinding contributor -n tenant-demo \
  --type='json' \
  -p='[{"op":"add","path":"/subjects/-","value":{"apiGroup":"rbac.authorization.k8s.io","kind":"User","name":"alice@example.com"}}]'
```

**Or use the script:**
```bash
./manage-user-roles.sh add alice@example.com contributor tenant-demo
```

**Say:** *"A team lead adds Alice to the contributor role. No tickets, no cluster-admin."*

---

### Step 5 — Verify access

```bash
# Alice CAN update deployments (contributor has update)
kubectl auth can-i update deployments -n tenant-demo --as=alice@example.com
# → yes

# Alice CANNOT delete pods (contributor has no delete)
kubectl auth can-i delete pods -n tenant-demo --as=alice@example.com
# → no
```

**Say:** *"Auth can-i confirms it — Alice can update but not delete. The tiered model works."*

---

### (Bonus) Step 6 — Drift correction demo

**Say:** *"Now watch what happens when someone tries to manually escalate the viewer role."*

```bash
# Show current viewer role
kubectl get role viewer -n tenant-demo -o jsonpath='{.rules[0].verbs}' | python3 -m json.tool
# → ["get", "list", "watch"]

# Manually add "delete" to viewer (BAD!)
kubectl apply -f 03-drift-test.yaml

# Wait ~5-10 seconds for Kyverno to reconcile
sleep 10

# Check again — "delete" is gone
kubectl get role viewer -n tenant-demo -o jsonpath='{.rules[0].verbs}' | python3 -m json.tool
# → ["get", "list", "watch"]
```

**Say:** *"Kyverno reverted the drift. With synchronize true, the policy is the source of truth. You physically cannot hand-edit your way to a privilege escalation."*

---

## Fallback: If Demo Fails

1. **Kyverno not ready:** Skip live demo, show pre-recorded terminal GIF
2. **Slow generation:** `kubectl get updaterequests -A` to check Kyverno queue
3. **Drift doesn't revert fast enough:** Say "Kyverno reconciles on its background scan interval — in production this is seconds, on this demo cluster it may take longer"

---

## Post-Demo Cleanup

```bash
./00-cleanup.sh
```

---

## Terminal Setup Tips

- Font size: **18pt+** (audience needs to read commands)
- Terminal theme: dark background, high contrast text
- Prompt: short (`$` not full path)
- Pre-type long commands in a scratch buffer, paste into terminal
- Have a split terminal: top = commands, bottom = `watch kubectl get role,rolebinding -n tenant-demo`
