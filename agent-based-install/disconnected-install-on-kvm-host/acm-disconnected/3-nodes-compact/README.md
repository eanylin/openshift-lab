## Deploy the managed cluster
- Create a namespace and directory to manage the cluster
```
$ mkdir cluster2-install
$ cd cluster2-install
$ oc new-project cluster2
```

- Create the `NMStateConfig` objects, which configures the network for each of the nodes and is used by the `InfraEnv` object in the next step
```
$ oc create -f nmstateconfig-master-0.yaml
$ oc create -f nmstateconfig-master-1.yaml
$ oc create -f nmstateconfig-master-2.yaml
```

- Create `Secret` containing the pull secret
```
$ oc create -f pull-secret.yaml
```

- Create `ClusterDeployment`, which manages the deployment of the cluster
```
$ oc create -f cluster-deployment.yaml
```

- Create the `AgentClusterInstall`, which defines the configuration of the cluster
```
$ oc create -f agent-cluster-install.yaml
```

- Create the `InfraEnv`, which generates the discovery ISO for us to boot the nodes
```
$ oc create -f infra-env.yaml
```

- Boot the hosts
    - Web Console → All Clusters → Infrastructure → Host inventory → Select Infra Env → Add hosts → With Discovery ISO → Download Discovery ISO
    - Boot up each of the nodes with the Discovery ISO and wait for them to be discovered
    - Back in the Infra Env page, select "Hosts" tab → Approve all the 3 master nodes → Monitor the installation
    - From the sidebar, select Infrastructure → Clusters → Select the installing cluster → Download kubeconfig
 
- Verify successful installation of the managed cluster
```
$ watch "oc get nodes,co --kubeconfig=<kubeconfig_path>"
```

- Import Cluster
    - For the cluster to be managed by RHACM, it has to be imported to RHACM by following these steps:
        - Infrastructure → Clusters → Import cluster → Choose either of the 3 options to import and follow through → Wait for import to complete
