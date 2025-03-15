#!/bin/bash

if ! kind get clusters | grep kind >/dev/null; then
  echo Creating local cluster...
  kind create cluster
fi

if [[ "$(kubectl config current-context)" != "kind-kind" ]]; then
  echo "Wrong kubeconfig..."
  exit 1
fi

echo "Installing ArgoCD..."
echo "=================================================="
kubectl apply -k argocd/install
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server --namespace argocd --timeout=300s

kubectl -n argocd port-forward svc/argocd-server 8443:443 &
argo_portforward_pid=$!

trap '{
    kill $argo_portforward_pid
}' EXIT

ARGOCD_ADMIN_SECRET=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Temporary JWT token
ARGOCD_ADMIN_TOKEN=$(curl -s -X POST -k -H "Content-Type: application/json" --data '{"username":"admin","password":"'$ARGOCD_ADMIN_SECRET'"}' https://localhost:8443/api/v1/session | jq -r .token)

# Create Token for provider-argocd
ARGOCD_PROVIDER_USER="provider-argocd"
ARGOCD_TOKEN=$(curl -s -X POST -k -H "Authorization: Bearer $ARGOCD_ADMIN_TOKEN" -H "Content-Type: application/json" https://localhost:8443/api/v1/account/$ARGOCD_PROVIDER_USER/token | jq -r .token)

kubectl create namespace crossplane-system || true
kubectl create secret generic argocd-credentials -n crossplane-system --from-literal=authToken="$ARGOCD_TOKEN"

echo "Bootstrap applications..."
kubectl apply -f root-argocd-app.yaml
