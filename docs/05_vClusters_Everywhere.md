# vClusters Everywhere

Let's get to the finish line 🏃‍♀️🏃‍♂️. In this section we will act as a consumer of our platform - i.e. a development team that requires access to a dedicated K8s cluster. 

## ArgoCD Apps

We will begin by adding an ApplicationSet again, this time with a `cluster`-Generator. The resource will create an ArgoCD application for each cluster that was registered in ArgoCD containing the label `managed-by: "crossplane"`. Add the following code to `appsets/sample-app.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - clusters:
        selector:
          matchLabels:
            managed-by: "crossplane"
  template:
    metadata:
      name: '{{.name}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps.git
        targetRevision: HEAD
        path: guestbook
      destination:
        server: '{{.server}}'
        namespace: guestbook
      syncPolicy:
        syncOptions:
        - CreateNamespace=true
        automated:
          prune: true
          selfHeal: true
```

Monitor the ArgoCD UI - nothing should happen just yet. Note that while the use case of deploying a random app might seem unclear, this could i.e. be company standard solutions like monitoring, security, etc. that should run in each K8s cluster by policy.

---

In our system, we decide to do everything via GitOps - thus we also want to deploy our `VirtualCluster` manifests via GitOps. In the real world, this could be a dedicated repository, however in this session, we will add them in this repo. Create a directory `tenants`. Now add the following ArgoCD Application Code that will automatically apply all the tenant manifests:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tenants
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/<your-github-name>/<your-repo-name>.git
    targetRevision: HEAD
    path: tenants
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

## Deploying Clusters

We finally have everything in place. Before testing it, let us recap what will happen:

1. A developer will create a Pull Request adding a new VirtualCluster as a YAML file (e.g. `<team-name>.yaml`) to `tenants/`
2. The ArgoCD app tenants will pick it up and apply it to the cluster
3. Crossplane will deploy the vCluster helm chart 
4. Crossplane will wait for the new vCluster to be available
5. Crossplane will register the new vCluster in ArgoCD
6. ArgoCD will deploy the `sample-app` into the new Cluster right away

Go ahead and add a file to the `tenants` directory. The content should look something like this:

```yaml
apiVersion: idp.lieberlois/v1alpha1
kind: VirtualCluster
metadata:
  name: your-team-name
spec: {}
```

Push this to GitHub. Watch the ArgoCD App `tenants` in the ArgoCD UI. Since ArgoCD only syncs every 3 minutes by default, feel free to click **Refresh** to speed things up here.

Once the VirtualCluster is applied, you can monitor the Crossplane resources using kubectl by running `kubectl get managed`. This shows all resources managed by Crossplane. Wait until everything is marked as ready. Once that is done, explore the ArgoCD UI. Look for the following two things.

  * The newly registered cluster (check in the settings)
  * The sample app, deployed to the new vCluster

Did this all work? Amazing ⭐⭐⭐

---

Great job on deploying your first VirtualCluster! To round things off, let us access the VirtualCluster and see what it looks like. You can use the vCluster CLI for this, but it's simpler to just extract the Kubeconfig.

Fetch the Kubeconfig of your vCluster. You can use the following command that will fetch the secret, access the path where the Kubeconfig is stored, base64 decode it and finally write it to a file CONFIG. You will need to find the name of the vCluster namespace for this - use `kubectl get namespace`, it should be obvious which one it is.

```bash
kubectl get secret -n <your-vcluster-namespace> vcluster-kubeconfig -o jsonpath='{.data.config}' | base64 -d > CONFIG
```

Finally create a port-forward to the Kube API of the vCluster. In the real world, this can be exposed e.g. using an Ingress. Find the name of the Kube API service using `kubectl get service -n <your-vcluster-namespace>`. It should be called `<your-vcluster-namespace>-vcluster`. Create a port-forward using `k port-forward -n <your-vcluster-namespace> svc/<your-vcluster-service> 8443:443`. 

Now access the vCluster by prefixing kubectl commands with the `KUBECONFIG` variable pointing to the path of the config we extracted in the previous step:

```bash
KUBECONFIG=CONFIG kubectl get pods
```

---

Great Job 🎉🎉 you have successfully completed this section! To clean up all of what you did, run `kind delete cluster`.