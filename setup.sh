#!/bin/bash

if ! kind get clusters | grep kind >/dev/null; then
  echo Creating local cluster...
  kind create cluster --config kind-config.yaml
fi

if [[ "$(kubectl config current-context)" != "kind-kind" ]]; then
  echo "Wrong kubeconfig..."
  exit 1
fi

echo "Installing ArgoCD..."
echo "=================================================="
kubectl apply -k argocd/install

echo Waiting a bit for ArgoCD pods to get created
sleep 5

kubectl wait --for=condition=ready pod --namespace argocd --timeout=300s --all

while ! kubectl get secret -n argocd argocd-initial-admin-secret 2>&1 >/dev/null; do
  echo Waiting for ArgoCD initial admin secret to exist...
  sleep 1
done

kubectl -n argocd port-forward svc/argocd-server 8443:443 2>&1 >/dev/null &
argo_portforward_pid=$!

trap '{
    kill $argo_portforward_pid
}' EXIT

while ! nc -vz localhost 8443 >/dev/null 2>&1; do
  echo Waiting for ArgoCD server to become reachable...
  sleep 1
done

echo "Fetching ArgoCD admin credentials from cluster..."
ARGOCD_ADMIN_SECRET=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

if [[ -z "$ARGOCD_ADMIN_SECRET" ]]; then
  echo "Failed to fetch admin credentials!"
  exit 1
fi

# Temporary JWT token
echo "Create temporary JWT token..."
ARGOCD_ADMIN_TOKEN=$(curl -s -X POST -k -H "Content-Type: application/json" --data '{"username":"admin","password":"'$ARGOCD_ADMIN_SECRET'"}' https://localhost:8443/api/v1/session | jq -r .token)

if [[ -z "$ARGOCD_ADMIN_TOKEN" ]]; then
  echo "Failed to create JWT token..."
  exit 1
fi

# Create Token for provider-argocd
ARGOCD_PROVIDER_USER="provider-argocd"
ARGOCD_TOKEN=$(curl -s -X POST -k -H "Authorization: Bearer $ARGOCD_ADMIN_TOKEN" -H "Content-Type: application/json" https://localhost:8443/api/v1/account/$ARGOCD_PROVIDER_USER/token | jq -r .token)

if [[ -z "$ARGOCD_TOKEN" || "null" == "$ARGOCD_TOKEN" ]]; then
  echo "Failed to create JWT token..."
  exit 1
fi

kubectl create namespace crossplane-system || true
kubectl create secret generic argocd-credentials -n crossplane-system --from-literal=authToken="$ARGOCD_TOKEN" || true
kubectl get secret -n crossplane-system argocd-credentials -o yaml

echo "Bootstrap applications..."
kubectl apply -f root-argocd-app.yaml
