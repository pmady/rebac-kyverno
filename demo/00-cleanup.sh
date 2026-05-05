#!/usr/bin/env bash
# =============================================================================
# 00-cleanup.sh — Reset cluster to pre-demo state
# KyvernoCon Virtual 2026 — Pavan Madduri
#
# Usage:  ./00-cleanup.sh
# Safe:   Only deletes resources created by the demo
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🧹 Cleaning up KyvernoCon demo resources...${NC}"
echo ""

# Delete demo namespace (and all resources inside it)
echo -e "Deleting namespace tenant-demo..."
kubectl delete namespace tenant-demo --ignore-not-found=true 2>/dev/null && \
  echo -e "${GREEN}✓${NC} Namespace tenant-demo deleted" || \
  echo -e "${YELLOW}⚠${NC} Namespace tenant-demo not found (already clean)"

echo ""

# Delete ClusterPolicies
POLICIES=(
  "generate-operator-role"
  "generate-contributor-role"
  "generate-viewer-role"
  "generate-operator-binding"
  "generate-contributor-binding"
  "generate-viewer-binding"
  "require-tenant-owner-label"
  "require-rebac-managed-label"
)

echo "Deleting ClusterPolicies..."
for p in "${POLICIES[@]}"; do
  kubectl delete clusterpolicy "$p" --ignore-not-found=true 2>/dev/null && \
    echo -e "${GREEN}✓${NC} ClusterPolicy $p deleted" || true
done

echo ""
echo -e "${GREEN}✓ Cleanup complete.${NC}"
echo ""
echo "Ready for next demo run:"
echo "  kubectl apply -f 01-rebac-policies.yaml"
echo "  kubectl apply -f 02-tenant-trigger.yaml"
