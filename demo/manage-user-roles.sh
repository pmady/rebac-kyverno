#!/bin/bash

# User Role Management - Scalable Approach
# Manages users in 3 static RoleBindings (operator, contributor, viewer)
# No individual RoleBindings per user

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

if [ $# -lt 2 ]; then
    print_error "Usage:"
    echo "  $0 add <email> <role> <namespace>"
    echo "  $0 remove <email> <role> <namespace>"
    echo "  $0 list <role> [namespace]"
    echo ""
    echo "Operations:"
    echo "  add     - Add user to role (updates static RoleBinding)"
    echo "  remove  - Remove user from role"
    echo "  list    - List all users in role"
    echo ""
    echo "Roles:"
    echo "  operator   - Full permissions"
    echo "  contributor - No delete permissions"
    echo "  viewer     - Read-only"
    echo ""
    echo "Examples:"
    echo "  $0 add jane.doe@platform.io contributor my-namespace"
    echo "  $0 remove jane.doe@platform.io contributor my-namespace"
    echo "  $0 list contributor my-namespace"
    echo "  $0 list operator"
    exit 1
fi

OPERATION="$1"

# Validate operation
if [[ ! "$OPERATION" =~ ^(add|remove|list)$ ]]; then
    print_error "Invalid operation: $OPERATION (use add, remove, or list)"
    exit 1
fi

# For list: args are <role> [namespace]
# For add/remove: args are <email> <role> <namespace>
if [[ "$OPERATION" == "list" ]]; then
    ROLE="$2"
    NAMESPACE="${3:-}"
    USER_EMAIL=""
else
    if [ $# -lt 4 ]; then
        print_error "Usage: $0 $OPERATION <email> <role> <namespace>"
        exit 1
    fi
    USER_EMAIL="$2"
    ROLE="$3"
    NAMESPACE="$4"
fi

# Validate role
if [[ ! "$ROLE" =~ ^(operator|contributor|viewer)$ ]]; then
    print_error "Invalid role: $ROLE (use operator, contributor, or viewer)"
    exit 1
fi

# RoleBinding name (3 static ones per namespace)
ROLEBINDING_NAME="${ROLE}"

case $OPERATION in
    add)
        print_info "Adding user to role"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "User:      $USER_EMAIL"
        echo "Role:      $ROLE"
        echo "Namespace: $NAMESPACE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # Check if namespace exists
        print_info "Checking if namespace exists..."
        if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
            print_error "Namespace '$NAMESPACE' does not exist"
            exit 1
        fi
        print_success "Namespace exists"
        
        # Check if RoleBinding exists
        print_info "Checking if RoleBinding exists..."
        if ! kubectl get rolebinding "$ROLEBINDING_NAME" -n "$NAMESPACE" &>/dev/null; then
            print_error "RoleBinding '$ROLEBINDING_NAME' does not exist in namespace"
            echo "This namespace may not be enabled. Create it first with generate-roles policy."
            exit 1
        fi
        print_success "RoleBinding '$ROLEBINDING_NAME' exists"
        
        # Check if user already exists
        print_info "Checking if user is already assigned..."
        if kubectl get rolebinding "$ROLEBINDING_NAME" -n "$NAMESPACE" -o jsonpath='{.subjects[*].name}' | grep -q "$USER_EMAIL"; then
            print_warning "User '$USER_EMAIL' is already assigned to this role"
            exit 0
        fi
        
        # Add user to RoleBinding subjects
        print_info "Adding user to RoleBinding subjects..."
        
        # Get current subjects (handles null/empty subjects from Kyverno-generated bindings)
        CURRENT_SUBJECTS=$(kubectl get rolebinding "$ROLEBINDING_NAME" -n "$NAMESPACE" -o json | jq '.subjects // []')
        
        # Append new user
        NEW_SUBJECTS=$(echo "$CURRENT_SUBJECTS" | jq --arg user "$USER_EMAIL" '. + [{"apiGroup": "rbac.authorization.k8s.io", "kind": "User", "name": $user}]')
        
        kubectl patch rolebinding "$ROLEBINDING_NAME" -n "$NAMESPACE" \
            --type=merge \
            -p="{\"subjects\": $(echo "$NEW_SUBJECTS" | jq -c .)}" \
            2>&1 | grep -v "^rolebinding.rbac.authorization.k8s.io" || true
        
        # Record audit
        kubectl patch rolebinding "$ROLEBINDING_NAME" -n "$NAMESPACE" \
            --type=merge \
            -p="{\"metadata\": {\"annotations\": {\"rebac.platform.io/last-updated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"rebac.platform.io/last-added-user\": \"${USER_EMAIL}\"}}}" \
            2>&1 | grep -v "^rolebinding.rbac.authorization.k8s.io" || true
        
        print_success "User '$USER_EMAIL' added to role '$ROLE'"
        echo ""
        echo "Current subjects in $ROLEBINDING_NAME:"
        kubectl get rolebinding "$ROLEBINDING_NAME" -n "$NAMESPACE" -o jsonpath='{.subjects[*].name}' | tr ' ' '\n' | nl
        ;;
        
    remove)
        print_info "Removing user from role"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "User:      $USER_EMAIL"
        echo "Role:      $ROLE"
        echo "Namespace: $NAMESPACE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # Check if namespace exists
        print_info "Checking if namespace exists..."
        if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
            print_error "Namespace '$NAMESPACE' does not exist"
            exit 1
        fi
        print_success "Namespace exists"
        
        # Check if RoleBinding exists
        print_info "Checking if RoleBinding exists..."
        if ! kubectl get rolebinding "$ROLEBINDING_NAME" -n "$NAMESPACE" &>/dev/null; then
            print_error "RoleBinding '$ROLEBINDING_NAME' does not exist"
            exit 1
        fi
        print_success "RoleBinding exists"
        
        # Check if user exists
        print_info "Checking if user is assigned..."
        SUBJECTS=$(kubectl get rolebinding "$ROLEBINDING_NAME" -n "$NAMESPACE" -o jsonpath='{.subjects[*].name}')
        if ! echo "$SUBJECTS" | grep -q "$USER_EMAIL"; then
            print_warning "User '$USER_EMAIL' is not assigned to this role"
            exit 0
        fi
        
        # Get current subjects
        CURRENT_SUBJECTS=$(kubectl get rolebinding "$ROLEBINDING_NAME" -n "$NAMESPACE" -o json | jq '.subjects // []')
        
        # Remove user from subjects
        print_info "Removing user from RoleBinding..."
        NEW_SUBJECTS=$(echo "$CURRENT_SUBJECTS" | jq --arg user "$USER_EMAIL" '[.[] | select(.name != $user)]')
        
        kubectl patch rolebinding "$ROLEBINDING_NAME" -n "$NAMESPACE" \
            --type=merge \
            -p="{\"subjects\": $(echo "$NEW_SUBJECTS" | jq -c .), \"metadata\": {\"annotations\": {\"rebac.platform.io/last-updated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"rebac.platform.io/last-removed-user\": \"${USER_EMAIL}\"}}}" \
            2>&1 | grep -v "^rolebinding.rbac.authorization.k8s.io" || true
        
        print_success "User '$USER_EMAIL' removed from role '$ROLE'"
        echo ""
        echo "Current subjects in $ROLEBINDING_NAME:"
        kubectl get rolebinding "$ROLEBINDING_NAME" -n "$NAMESPACE" -o jsonpath='{.subjects[*].name}' | tr ' ' '\n' | nl || echo "(none)"
        ;;
        
    list)
        # List can work with or without namespace
        if [ -z "$NAMESPACE" ]; then
            print_info "Listing all users with role: $ROLE"
            echo ""
            echo "Select namespace or press Enter to show all:"
            read -p "> " LIST_NS
            
            if [ -z "$LIST_NS" ]; then
                echo ""
                echo "RoleBindings with name $ROLE in all namespaces:"
                kubectl get rolebindings -A --no-headers 2>/dev/null | grep " $ROLE " || \
                echo "(none found)"
            else
                NAMESPACE="$LIST_NS"
            fi
        fi
        
        if [ -n "$NAMESPACE" ]; then
            print_info "Listing users in role '$ROLE' (namespace: $NAMESPACE)"
            echo ""
            kubectl get rolebinding "${ROLE}" -n "$NAMESPACE" -o jsonpath='{.subjects[*].name}' 2>/dev/null | wc -w | xargs echo "Total users:"
            echo ""
            echo "Users:"
            kubectl get rolebinding "${ROLE}" -n "$NAMESPACE" -o jsonpath='{.subjects[*].name}' 2>/dev/null | tr ' ' '\n' | nl || echo "(none)"
        fi
        ;;
esac

echo ""
print_success "Operation completed successfully"
echo ""
