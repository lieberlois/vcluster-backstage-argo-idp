# Crossplane XRDs

In this section we will now implement the actual "Kubernetes as a Service" part leveraging Crossplane 🛠️. For this we require two Crossplane resources:

1. **CompositeResourceDefinition** (XRD)

    An XRD defines the schema for a custom API and thus creates a Custom Resource Definition in Kubernetes. The difference to a normal CustomResourceDefinition is mainly the integration with Crossplane. 

2. **Composition**

    The composition is now the central part for todays workshop. If you have ever developed a Kubernetes Operator, this is similar to the controller logic - it is, what gives life to the XRD. In the operator world, this is e.g. responsible for creating Deployments, Services, etc. or requesting Certificates in the example of cert-manager.

---

Let's first start by designing our API. This is the central engineering part, since it is what we will expose to our developers / customers to our platform. For our workshop, I will take this off your hands. We will define that we want a customer to only be able to create their own cluster, with no additional configuration except for a name. All of this will be done via YAML and might look like this:

```yaml
apiVersion: idp.lieberlois/v1alpha1
kind: VirtualCluster
metadata:
  name: example-team-123
spec: {}
```

To be able to expose this in our Kubernetes-Cluster we need to create a CompositeResourceDefintion. This is as simple as deploying a Custom Resource `CompositeResourceDefinition` containing an OpenAPI spec of the YAML spec to our cluster. Create a file `crossplane/xrds/xvirtualcluster/definition.yaml` with the following content:

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xvirtualclusters.idp.lieberlois
spec:
  group: idp.lieberlois
  names:
    kind: XVirtualCluster
    plural: xvirtualclusters
  claimNames:
    kind: VirtualCluster
    plural: virtualclusters
  versions:
  - name: v1alpha1
    served: true
    referenceable: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              vcluster:
                type: object
                properties:
                  values:
                    description: Values for vcluster Helm chart
                    type: object
```

Now to the final and most complex step: the implementation of the backing logic of the XRD: the Composition. Since we will add ~150 lines of YAML code, we will only go through the central steps. The Composition will have a reference to our newly created XRD in the field `spec.compositeTypeRef`. In `spec.resources`, we can see how Crossplane will manage the setup of a Kubernetes cluster for us. Let us first add this block of YAML to `crossplane/xrds/xvirtualcluster/composition.yaml`:

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: virtualcluster
  labels:
    crossplane.io/xrd: xvirtualclusters.idp.lieberlois
    provider: helm
spec:
  compositeTypeRef:
    apiVersion: idp.lieberlois/v1alpha1
    kind: XVirtualCluster
  resources:
  - name: vcluster
    base:
      apiVersion: helm.crossplane.io/v1beta1
      kind: Release
      name: vcluster-test
      spec:
        forProvider:
          chart:
            name: vcluster
            repository: https://charts.loft.sh
            version: 0.23.0
          namespace: vcluster-test
          values:
            controlPlane:
              proxy:
                extraSANs:
                  - vcluster-test.vcluster-test.svc.cluster.local
            exportKubeConfig:
              secret:
                name: vcluster-kubeconfig
              server: https://vcluster-test.vcluster-test.svc.cluster.local
        providerConfigRef:
          name: helm-provider
    patches:
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.namespace
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: metadata.name
      transforms:
      - type: string
        string:
          fmt: "%s-vcluster"
    - type: CombineFromComposite
      combine:
        variables:
        - fromFieldPath: metadata.name
        - fromFieldPath: metadata.name
        strategy: string
        string:
          fmt: "%s-vcluster.%s.svc.cluster.local"
      toFieldPath: spec.forProvider.values.controlPlane.proxy.extraSANs[0]
    - type: CombineFromComposite
      combine:
        variables:
        - fromFieldPath: metadata.name
        - fromFieldPath: metadata.name
        strategy: string
        string:
              fmt: "https://%s-vcluster.%s.svc.cluster.local"
      toFieldPath: spec.forProvider.values.exportKubeConfig.server
  - name: argo-cluster
    base:
      apiVersion: cluster.argocd.crossplane.io/v1alpha1
      kind: Cluster
      name: vcluster-test
      spec:
        forProvider:
          labels:
            managed-by: crossplane
          config:
            kubeconfigSecretRef:
              key: config
              name: vc-vcluster-test-vcluster
              namespace: vcluster-test
          name: vcluster-test
        providerConfigRef:
          name: argocd-provider
    patches:
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.config.kubeconfigSecretRef.namespace
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.config.kubeconfigSecretRef.name
      transforms:
      - type: string
        string:
          fmt: "vc-%s-vcluster"
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: metadata.name
      transforms:
      - type: string
        string:
          fmt: "%s-argo-ref"
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.name
  - name: cluster-usage
    base:
      apiVersion: apiextensions.crossplane.io/v1beta1
      kind: Usage
      name: argo-cluster-uses-helm-release
      spec:
        of:
          apiVersion: helm.crossplane.io/v1beta1
          kind: Release
          resourceRef:
            name: vcluster-test
        by:
          apiVersion: cluster.argocd.crossplane.io/v1alpha1
          kind: Cluster
          resourceRef:
            name: my-prometheus-chart
    patches:
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: spec.of.resourceRef.name
      transforms:
      - type: string
        string:
          fmt: "%s-vcluster"
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: spec.by.resourceRef.name
      transforms:
      - type: string
        string:
          fmt: "%s-argo-ref"
  - name: observe-delete-namespace
    base:
      apiVersion: kubernetes.crossplane.io/v1alpha1
      kind: Object
      metadata:
        name: foo
      spec:
        managementPolicy: ObserveDelete
        forProvider:
          manifest:
            apiVersion: v1
            kind: Namespace
        providerConfigRef:
          name: kubernetes-provider
    patches:
    - type: FromCompositeFieldPath
      fromFieldPath: metadata.name
      toFieldPath: metadata.name
```

Now to the explanation of the resources.

1. **name: vcluster**

    Uses the Crossplane Helm Provider to deploy the vCluster helm chart. In the `patches` section of the resource you can see how values from the XRD are being used to set parameters like the resource namespace or a SAN (Subject Alternative Name) for the vCluster Kubeconfig.

2. **name: argo-cluster**

    Uses the Crossplane ArgoCD Provider to register the newly created vCluster in ArgoCD. As you can see in the spec of this resource, it will reference the Kubeconfig that was created by the vCluster Helm Release. The exact name of the secret will again be overwritten in the `patches` section.

3. **name: cluster-usage** 

    This is a meta-resource that only specificies an explicit dependency between resources. In this case, it makes sure that when deleting one of our custom `VirtualCluster` resources, that the resources managed by the Composition will be cleaned up in the correct order.

3. **name: observe-delete-namespace**

    This is also a meta-resource. Since we create a namespace per VirtualCluster, we will add this resource to make sure, the namespaces are deleted upon deletion of our VirtualClusters.

---

FInally, we need to add the ArgoCD Application for XRDs. We will again use an ApplicationSet similar to the deployment of the Crossplane Providers. Append the following YAML code to `appsets/crossplane.yaml`. Make sure to keep the `---` separator between the manifests:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: crossplane-xrds
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
        - path: crossplane/xrds/*
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

---

Commit and push all of this to GitHub. Now monitor the ArgoCD UI and make sure everything spins up nicely. Feel free to also check the K8s pods using `kubectl get pods -A`.