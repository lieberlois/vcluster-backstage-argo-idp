# Welcome 👋

Hello and Servus zusammen to the workshop about setting up a `Self Service IdP with Argo & Crossplane`.

In this session, we will set up an MVP for a Self-Service Internal Developer Platform, in which
clients (i.e. developer teams) can set up Kubernetes clusters with ease, following `Golden Paths`
that we as platform engineers can design beforehand. As is common practice in the industry,
we will leverage GitOps wherever we can, always leaving our desired state in our Version Control System, 
in our case: GitHub. We will use ArgoCD to sync our desired state into our Kubernetes cluster.

Since provisioning real K8s clusters in the cloud can take time, and I want to save money, we will be using
the great technology [vCluster](https://www.vcluster.com/) for this. With vCluster, we can run virtual K8s 
clusters within a common host cluster, enabling us to efficiently use our resources while maintaining proper
tenancy isolation.

Lastly, for glueing everything together we will use [Crossplane](https://www.crossplane.io/). The docs describe
it as a "Cloud-Native Framework for Platform Engineering" which exactly fits our needs. Deploying clusters,
registering their credentials in Argo, you want it - Crossplane can do it! 💪

## Prerequisites 🛠️

Somebody said Kubernetes? For this demo, each team will set up the whole stack locally. For K8s, we will use
[kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) - which is a tool for spinning up a K8s 
cluster within a Docker container locally. For the interaction with our K8s clusters, we will of course use
[kubectl](https://kubernetes.io/docs/reference/kubectl/). You will also need a new public GitHub repository 
for this workshop. You can use a private one, but the guide does not include setting up authentication between
ArgoCD and GitHub.

**Note for MacOS users:** Since you will be running Docker in a VM and we will start up quite some pods, I would
recommend allocating enough resources to the Virtual Machine. I used [Colima](https://github.com/abiosoft/colima)
with the following startup command: `colima start --dns 8.8.8.8 --dns 1.1.1.1 --memory 6 --cpu 3`.

Through the course of this guide, the `main` branch of this repository contains all manifests etc. in the final state. If you get stuck or want to compare your solution, feel free to check it out whenever you want.

---

Now without further ado, let's get started! 🚀