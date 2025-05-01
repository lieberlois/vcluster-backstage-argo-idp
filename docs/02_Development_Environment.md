# Development Environment

In this section, we will set up our local environment. If you have no Container Runtime running,
start this now. On MacOS I used `colima start --dns 8.8.8.8 --dns 1.1.1.1 --memory 6 --cpu 3` for this.
You can check if everything is running properly using `docker ps` (or Podman, or whatever CLI you are using).

## Kubernetes 🐳

Let us now set up our local K8s cluster. This is as simple as running `kind create cluster`. After this is run, double-check that your local K8s context was properly set so you don't delete customer infrastructure by accident 😉 running `kubectl config current-context` should output "kind-kind". If you now run `kubectl get pods -A`, you should see a new and clean K8s cluster running on your local machine!

## ArgoCD

Next, we want to set up ArgoCD in our local cluster. If you have this repository cloned, you can use the files in the [ArgoCD directory](../argocd/install/) by running `kubectl apply -k argocd/install` from the repository root. ArgoCD will automatically deploy in your cluster now. 

This is almost a plain ArgoCD installation with one addition: a new ArgoCD user called `provider-argocd` that we will later use to register our new clusters in ArgoCD. For this user, we also enable the option of using an apiKey instead of credentials. Note that this is just for explanation of what is happening, nothing needs to be done from your side.

Monitor the `argocd` namespace to assert everything is up and running using `kubectl get pods -n argocd`. As soon as everything is up, you can now get the credentials for ArgoCD, create a port-forward and finally connect to the ArgoCD UI. 

```bash
# Fetch ArgoCD admin secret, access only the password and run a base64 decode.
# Write this password down somewhere for convenient access.
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Create a port-forward to ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8443:443
```

You should now be able to access [ArgoCD](https://localhost:8443). The certificate is unsigned, so it is only natural that your
browser will not trust it by default. In Google Chrome, you can bypass this by just typing `thisisunsafe` on your keyboard 💻.

## Creating our first ArgoCD application

In this setup, we will use the [App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-bootstrapping/#app-of-apps-pattern). This means, that we will have one ArgoCD application that will transitively set up all other applications, enabling a "zero" (or single 🤫) touch deployment. Create a file `root-argocd-app.yaml` with the following content (substitute the variables of course):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: all-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-github-name>/<your-repo-name>.git
    targetRevision: main
    path: appsets
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    automated:
      prune: true
      selfHeal: true
```

This ArgoCD application will function as our "root application". In the line `spec.source.path` you can see the path in the repository defined at `spec.source.repoURL` that this application will be monitoring. Since we point the app at a directory called `appsets`, let's  create an empty directory at the repository root and then push it into our GitHub repository. Now check the ArgoCD to see the first application.

## Create ArgoCD User Token

For later purposes, we need to create a token for a technical ArgoCD user, so Crossplane can later access the ArgoCD API. This can be done using the following commands:

```bash
# Assert ArgoCD is reachable. If not, restart the port-forward mentioned above
# Can be tested e.g. using netcat as follows:
nc -vz localhost 8443 

# Fetching ArgoCD admin credentials from cluster...
ARGOCD_ADMIN_SECRET=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Temporary JWT token
ARGOCD_ADMIN_TOKEN=$(curl -s -X POST -k -H "Content-Type: application/json" --data '{"username":"admin","password":"'$ARGOCD_ADMIN_SECRET'"}' https://localhost:8443/api/v1/session | jq -r .token)

# Create Token for provider-argocd
ARGOCD_PROVIDER_USER="provider-argocd"
ARGOCD_TOKEN=$(curl -s -X POST -k -H "Authorization: Bearer $ARGOCD_ADMIN_TOKEN" -H "Content-Type: application/json" https://localhost:8443/api/v1/account/$ARGOCD_PROVIDER_USER/token | jq -r .token)

# Store Token in K8s secret
kubectl create namespace crossplane-system || true
kubectl create secret generic argocd-credentials -n crossplane-system --from-literal=authToken="$ARGOCD_TOKEN" || true

# Assert the secret contains a token and not "null" or similar - if not, try again or reach out for help
kubectl get secret -n crossplane-system argocd-credentials -o yaml
```