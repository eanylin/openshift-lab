## Set up the required base configurations in the ACM Hub cluster
- Follow instructions in [documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.13/html/install/installing#install-on-disconnected-networks) to install the Red Hat Advanced Cluster Management for Kubernetes on the disconnected OpenShift cluster
- Adopt and deploy the following YAML files
    - Ensure that the `registries.conf` are properly populated, pointing to the relevant mirrored registry
    - The release image in the `ClusterImageSet` can be retrieved from the mirror registry
```
$ oc project multicluster-engine
$ oc create -f assisted-service-configmap.yaml
$ oc create -f cluster-image-set.yaml
$ oc create -f mirror-config-configmap.yaml
```
