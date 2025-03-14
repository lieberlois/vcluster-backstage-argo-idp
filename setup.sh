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
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Installing Argo Workflows..."
echo "=================================================="
export ARGO_WORKFLOWS_VERSION=3.5.4
kubectl create namespace argo || true
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v$ARGO_WORKFLOWS_VERSION/install.yaml
kubectl patch deployment \
  argo-server \
  --namespace argo \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": [
  "server",
  "--auth-mode=server"
]}]'

echo "Installing Argo Events..."
echo "=================================================="
kubectl create namespace argo-events || true
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install.yaml
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install-validating-webhook.yaml
kubectl apply -n argo-events -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml

echo "Initializing ClusterAPI..."
clusterctl init --infrastructure vcluster
kubectl create namespace vcluster

echo "Bootstrap ArgoCD..."
kubectl apply -f root-argocd-app.yaml

sleep 15

echo "Add argocd login credentials for Workflows..."
ARGO_PASSWORD=$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
kubectl create secret generic argocd-login --from-literal="password=${ARGO_PASSWORD}" --from-literal=username=admin -n argo
