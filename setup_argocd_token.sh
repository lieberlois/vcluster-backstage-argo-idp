#!/bin/bash

echo "Fetching ArgoCD admin credentials from cluster..."
ARGOCD_ADMIN_SECRET=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

if [[ -z "$ARGOCD_ADMIN_SECRET" ]]; then
  echo "Failed to fetch admin credentials!"
  exit 1
fi

# Temporary JWT token
echo "Create temporary JWT token..."
ARGOCD_ADMIN_TOKEN=$(curl -s -X POST -k -H "Content-Type: application/json" --data '{"username":"admin","password":"'$ARGOCD_ADMIN_SECRET'"}' https://argocd.cnoe.localtest.me:8443/api/v1/session | jq -r .token)

if [[ -z "$ARGOCD_ADMIN_TOKEN" ]]; then
  echo "Failed to create JWT token..."
  exit 1
fi

# Create Token for provider-argocd
ARGOCD_PROVIDER_USER="developer"
echo "Create token for user developer..."
ARGOCD_TOKEN=$(curl -s -X POST -k -H "Authorization: Bearer $ARGOCD_ADMIN_TOKEN" -H "Content-Type: application/json" https://argocd.cnoe.localtest.me:8443/api/v1/account/$ARGOCD_PROVIDER_USER/token | jq -r .token)

if [[ -z "$ARGOCD_TOKEN" ]]; then
  echo "Failed to create JWT token..."
  exit 1
fi

kubectl create secret generic argocd-credentials -n crossplane-system --from-literal=authToken="$ARGOCD_TOKEN" || true
kubectl get secret -n crossplane-system argocd-credentials -o yaml
