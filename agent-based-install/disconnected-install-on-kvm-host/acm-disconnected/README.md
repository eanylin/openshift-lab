## Set up the required multicluster egine configurations in the ACM Hub cluster
- Follow instructions in [documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.13/html/install/installing#install-on-disconnected-networks) to install the Red Hat Advanced Cluster Management for Kubernetes on the disconnected OpenShift cluster
- We will need to host `rhcos-live-rootfs.x86_64.img` and `rhcos-4.18.1-x86_64-live.x86_64.iso` either on a Apache Web Server or in a S3 Object Storage Bucket so that it can be download
    - The files can be download from [link1](https://mirror.openshift.com/pub/openshift-v4/amd64/dependencies/rhcos/4.18/4.18.1/rhcos-live-rootfs.x86_64.img) and [link2](https://mirror.openshift.com/pub/openshift-v4/amd64/dependencies/rhcos/4.18/4.18.1/rhcos-live.x86_64.iso) respectively
\
&nbsp;
- The Central Infrastructure Management (CIM) Service is part of the Multicluster Engine Operator, and it needs to be enabled as it runs the Assisted Installer
- Ensure that relevant ports are open
```
$ sudo ss -tuln | grep -E ':67|:68|:69|:80|:123|:5050|:5051|:6180|:6183|:6385|:6388|:8080|:8083|:9999'
$ sudo firewall-cmd --list-ports
```

- Enable the CIM by configuring AgentServiceConfig
```
$ oc project multicluster-engine
$ oc create -f agent-service-config.yaml
```

- Check that the pods are up and running properly
```
$ oc get pods -n multicluster-engine | grep -i assisted-service
$ oc get pods -n multicluster-engine | grep -i assisted-image-service
```

- Adopt and deploy the following YAML files
    - Ensure that the `registries.conf` are properly populated, pointing to the relevant mirrored registry
    - The release image in the `ClusterImageSet` can be retrieved from the mirror registry
        - Note that ClusterImageSet manages the images required for the cluster
```
$ oc create -f assisted-service-configmap.yaml
$ oc create -f cluster-image-set.yaml
$ oc create -f mirror-config-configmap.yaml
```
