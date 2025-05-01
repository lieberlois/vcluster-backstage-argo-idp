# Installing Crossplane

For installing Crossplane, let's get an overview of things we need to understand first. In my own words, I would describe Crossplane as an operator that can be extended using Custom Resource Definitions (CRDs). If you have not heard of this yet, CRDs extend the K8s API with new resources - so in addition to Pods, you might for example have a resource of kind `Certificate` in the case of cert-manager.

## Deploy Crossplane Operator

Let's first add a deployment of Crossplane itself. For this we will add a dedicated ArgoCD application which will point at our own umbrella chart. Create a file `crossplane/deployment/Chart.yaml` with the following content:

```yaml
apiVersion: v2
type: application
name: crossplane-argocd
version: 0.0.0 # unused
appVersion: 0.0.0 # unused
dependencies:
  - name: crossplane
    repository: https://charts.crossplane.io/stable
    version: 1.19.0
```

While ArgoCD has native helm support, this setup is more extensible since it enables easier future integrations with tooling like Renovate. The only thing remaining is to add the ArgoCD application. Add the following YAML code to `appsets/crossplane.yaml` and push it to GitHub:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: crossplane-deployment
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://github.com/<your-github-name>/<your-repo-name>.git
    targetRevision: HEAD
    path: crossplane/deployment
  destination:
    server: https://kubernetes.default.svc
    namespace: crossplane-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

Since the root app, that we created during the setup of our [Development Environment](02_Development_Environment.md), watches the `appsets` directory, we can now monitor the ArgoCD UI and should be able to see Crossplane come up slowly.

## Deploy Crossplane Providers

tbd.

Crossplane separates these APIs into `Providers`, which helps not to overload the K8s control plane with thousands of resources by only installing those that are required for the job. We will install the following resources:

  - Helm Provider: Deploy vClusters using the official Helm Chart
  - K8s Provider: Manage namespaces per vCluster (i.e. cleanup)
  - ArgoCD Provider: Register vClusters into ArgoCD

Copy the directory [providers](../crossplane/providers/) into your repository to `crossplane/providers`. Read through the manifests and get an overview what is being configured there. Since we will have all day, we will not dive to deep here. Let's add an ArgoCD ApplicationSet manifest. ApplicationSets use `generators` to dynamically create Applications. We will use this to create one Application per Crossplane Provider. Append the following manifest to `appsets/crossplane.yaml`. Make sure to keep the `---` separator between the manifests:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: crossplane-providers
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - git:
      repoURL: https://github.com/<your-github-name>/<your-repo-name>.git
      revision: HEAD
      directories:
        - path: crossplane/providers/*
      requeueAfterSeconds: 30
  template:
    metadata:
      name: '{{.path.basename}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/<your-github-name>/<your-repo-name>.git
        targetRevision: HEAD
        path: '{{.path.path}}'
        directory:
          recurse: true
      destination:
        namespace: default
        server: https://kubernetes.default.svc
      syncPolicy:
        syncOptions:
        - CreateNamespace=true
        automated:
          prune: true
          selfHeal: true
```

Commit this to GitHub. Now watch the providers be applied in the ArgoCD UI. It is a good time to run `kubectl get pods -A` to see the current state and look at all the pods that we already created.