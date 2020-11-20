# Direct access to VPC-native GKE master endpoint from a remote network

To help test the connectivity between a remote network and a Kubernetes master endpoint on a VPC-native GKE cluster,
I've created the Terraform code contained on this folder.

You will find the following sections:
- Description of the Test Scenario;
- Steps to deploy and reproduce the connection error;
- Discussion of the probable reason behind the network connectivity issue.

## Test scenario

To enable testing, the following infrastructure is deployed:

- A local network called `n0` with subnetwork called `cluster-subnetwork` where a VPC-native GKE cluster is deployed.
- A local test Linux GCE VM called `i0` is present with kubectl installed.
- A remote network called `n1` with a subnetwork called `remote-subnetwork` where a remote test Linux GCE VM called `i1`
is present with kubectl installed.
- An HA VPN connecting both `n0` and `n1` networks with Cloud Routers exchanging routes between themselves through a BGP
session.
- A custom route advertisement with GKE master CIDR IP range is set not the `n0`'s Cloud Router to make sure that `i1`
can send IP packets to the Kubernetes master endpoint.

The testing scenario is as follows:
1. Connect to the local test VM `i0` and successfully run a `kubectl get all` command;
2. Connect to the remote test VM `i1` and attempt to run a `kubectl get all` command which returns an `i/o timeout`
error.

## Steps to Deploy and Reproduce the issue

1. Set the project ID and unique ID environment variables (replacing `MY-PROJECT` first):
```shell script
export project_id="MY-PROJECT"
export unique_id="ug23"
```

1. Deploy the cluster and dependent resources:
```shell script
terraform init
terraform apply -var project_id=${project_id} -var unique_id=${unique_id}
```

1. Connect to the local test VM (i0-...)

1. Setup its environment and list Kubernetes resources:
```shell script
export project_id=$(curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)
export unique_id=$(curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/unique-id)
gcloud --project ${project_id} container clusters get-credentials cluster-${unique_id} --region europe-west2
kubectl get all
```

1. Exit the local test VM (i0-...) and connect to the remote test VM (i1-...):

1. Setup its environment and list Kubernetes resources:
```shell script
export project_id=$(curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)
export unique_id=$(curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/unique-id)
gcloud --project ${project_id} container clusters get-credentials cluster-${unique_id} --region europe-west2
kubectl get all
```

**Notice that the last command will fail to reach the Kubernetes API (i.e. the GKE master endpoint) even though the
custom route exists to transit traffic through the VPN tunnels and the cluster master authorized networks allows
requests from the remote-subnetwork's CIDR IP range.**

Here's an example of the error returned:
```
Unable to connect to the server: dial tcp 192.168.12.2:443: i/o timeout
```

1. Exit the remote test VM and destroy the test environment:
```shell script
exit
terraform destroy -var project_id=${project_id} -var unique_id=${unique_id}
```

## Discussion

The VPC-native GKE deployment automatically creates a VPC peering connections between the local VPC network called `n0`
and a VPC network automatically created by GCP to host the Kubernetes master nodes on tenant project fully managed by
GCP.

A VPC network peering connection can only be successfully established if both projects (the customer project and
the tenant project) have a peering connection resource configured referencing each other's VPC networks'. Only when
these references match the VPC network peering connection is successfully established and routes between the two VPC
networks are exchanged between themselves. During the VPC-native GKE cluster deployment both peering connection objects
are created by the Kubernetes API service agent with well defined parameters.
 
When a VPC network peering connection is established, all subnet routes for both VPC networks are exchanged between the
two peered networks by default and peered subnet routes (from other peered VPC networks) are not exchanged. This
behaviour cannot be changed. Custom routes (which include both static and dynamic routes) are not exchanged by default.
Custom routes from one VPC network, lets call it `vpc-a`, call only be exchanged with its peered VPC network, lets call
it `vpc-b` if `vpc-a` has the `export custom routes` feature enabled on its peering connection resource and `vpc-b` has
the `import custom routes` feature enabled on its peering connection resource.
 
Looking at the [Kubernetes Engine API reference](https://cloud.google.com/kubernetes-engine/docs/reference/rest/v1/projects.locations.clusters#Cluster) 
it appears that there isn't a parameter to change the import/export custom routes parameter of the peering, and this is
why the IP packets from `i1` VM never reach the Kubernetes endpoint.

## More information

* [Importing and exporting Routes](https://cloud.google.com/vpc/docs/vpc-peering#importing-exporting-routes)
* [Route types](https://cloud.google.com/vpc/docs/routes#types_of_routes)
