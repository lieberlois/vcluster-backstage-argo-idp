# Advanced Setup 

Disclaimer: This section should only be started if you have completed sections 1 through 5 and still have time and motivation left to experiment 🧠. All of the code for this section will be on the branch `variant/idpbuilder`. Switch to that branch now.

---

This section shows a variant of the previous sections in a more sophisticated setup. We will not go through every file, but will rather set it up and give you time to explore it all. What's different in this setup? The biggest difference is the use of a developer portal, in this case [Backstage by Spotify](https://backstage.io/). We will also use ExternalSecrets to sync secrets between namespaces so they are accessible where they're needed. Lastly, we use [Gitea](https://docs.gitea.com/) as our own Git server, so we can spin up repositories etc. on demand, thus being able to ideate and develop this Internal Developer Platform in faster iteration cycles without cluttering our real GitHub organization 👍

To simplify the setup, we will use the very helpful tool [idpbuilder](https://github.com/cnoe-io/idpbuilder) which allows us to "Spin up a complete internal developer platform using industry standard technologies like Kubernetes, Argo, and backstage with only Docker required as a dependency". In the default settings, it will create a platform consisting of a kind cluster, Gitea, ArgoCD (pointing to Gitea), an Ingress Controller and all of the configuration code of those applications stored in dedicated Gitea repositories. It will also configure DNS so you can resolve the hostnames of the resources exposed via Ingress locally.

## Set up the IDP basis

Make sure you stopped / deleted the setup from the previous sessions. Now let us download the `idpbuilder` binary. Follow the [installation guide](https://github.com/cnoe-io/idpbuilder?tab=readme-ov-file#getting-started).

Once this is done, spin up the basic platform using `./idpbuilder create`.

## Access the tooling 🛠️

Try to access Gitea and ArgoCD. The credentials can be found using `./idpbuilder get secrets`. 

- [ArgoCD](https://argocd.cnoe.localtest.me:8443/)
- [Gitea](https://gitea.cnoe.localtest.me:8443/)

Now that you have access feel free to explore the existing setup. Finish the step by adding your public SSH key to Gitea. You can do that by accessing the profile settings in the top right corner, 

## Configuring an ArgoCD Token

Similar to the previous sessions, we need to set up an ArgoCD user with a token and appropriate permissions. Since this setup a) ships a default configuration and b) manages ArgoCD via ArgoCD, the approach will be a bit different. In theory idpbuilder supports [customizations](https://cnoe.io/docs/intro/idpbuilder/override) of the installed tools, however there was a [bug (#515)](https://github.com/cnoe-io/idpbuilder/issues/515) at the time of writing this page.

1. Clone the ArgoCD repository from Gitea
2. Find the manifest of the ConfigMap `argocd-rbac-cm` in `resource1.yaml`
3. Change `g, developer, role:developer` to `g, developer, role:admin`
4. In a version I tested idpbuilder, the ConfigMap was in the file twice. Remove the second occurence if that is the case for you.
5. Push your changes to Gitea. Refresh the ArgoCD app in the UI.
6. Run the script [setup_argocd_token.sh](./../setup_argocd_token.sh) to create an ArgoCD token and store it in a K8s secret. Make sure the secret doesn't just contain `null` or similar. If it does, try to re-run / fix it or reach out for help.

## Spinning up the platform

We can now use the setup I prepared to spin up our entire IdP. Quick explanation of the repo structure. IdP builder discovery all of the ArgoCD Application and ApplicationSet manifests in the root directory. For each of those, it will create a Gitea repository with the content being the files at the path where the Application / ApplicationSet points to. 

Run the following command to spin this up: `./idpbuilder create -p .` Watch all of the apps being created. Once all is finished, access [Backstage](https://cnoe.localtest.me:8443/).

---

This is your time to explore. Try to create a VirtualCluster using Backstage and explore the created resources in the portal. You can for example jump to the ArgoCD app or view the state of the vCluster all within Backstage. Check the files in the [Backstage templates](../idp/backstage-templates/) to see how the integration works. You can also try to access the vCluster (no need for a port-forward this time, just fetch the Kubeconfig as described in the resource description in the Backstage UI).
