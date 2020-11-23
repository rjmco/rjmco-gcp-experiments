# Direct access to VPC-native GKE master endpoint from a remote network

To help test the connectivity between a remote network and a Kubernetes master endpoint on a VPC-native GKE cluster,
I've created the Terraform code contained on this folder.

You will find the following sections:
- Description of the Test Scenario;
- Steps to deploy and test the connection to K8s' master endpoint;
- Future work

## Test Scenario

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
2. Connect to the remote test VM `i1` and attempt to run a `kubectl get all` command;

## Requirements

Software:
* Terraform `>= 0.12`
* Google Cloud SDK

Cloud resources:
* A GCP project linked to a billing account with Compute and Container APIs enabled;
* Compute and Container Administrator roles on the project.

## Steps to Deploy and Reproduce the Test

* Set the project ID and unique ID environment variables (replacing `MY-PROJECT` first):

```shell script
export project_id="MY-PROJECT"
export region="europe-west2"
export unique_id="ug23"
```

* If not already done, setup application default authentication with Google Cloud SDK as follows:

```shell script
gcloud auth application-default login
```

* Deploy the cluster and dependent resources:

```shell script
terraform init
terraform apply -var project_id=${project_id} -var region=${region} -var unique_id=${unique_id}
```

* Fetch the VPC peering connection name and update it to export custom routes as follows:

```shell script
export network_name="$(gcloud --project ${project_id} container clusters describe cluster-${unique_id} --region ${region} --format='value(networkConfig.network.basename())')"
export peering_name="$(gcloud --project ${project_id} container clusters describe cluster-${unique_id} --region ${region} --format='value(privateClusterConfig.peeringName)')"
gcloud --project ${project_id} compute networks peerings update ${peering_name} --network ${network_name} --export-custom-routes
```

* Connect to the local test VM (i0-...)

* Setup its environment and list Kubernetes resources:

```shell script
export project_id="$(curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)"
export unique_id="$(curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/unique-id)"
export zone="$(basename $(curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone))"
export region="${zone:0:${#zone}-2}"
gcloud --project ${project_id} container clusters get-credentials cluster-${unique_id} --region ${region}
kubectl get all
```

* Exit the local test VM (i0-...) and connect to the remote test VM (i1-...):

* Setup its environment and list Kubernetes resources:

```shell script
export project_id="$(curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)"
export unique_id="$(curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/unique-id)"
export zone="$(basename $(curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone))"
export region="${zone:0:${#zone}-2}"
gcloud --project ${project_id} container clusters get-credentials cluster-${unique_id} --region ${region}
kubectl get all
```

* Exit the remote test VM and destroy the test environment:

```shell script
terraform destroy -var project_id=${project_id} -var region=${region} -var unique_id=${unique_id}
unset project_id region unique_id
```

* If necessary, revoke application default authentication as follows:

```shell script
gcloud auth application-default revoke
```

## Future work

Use `compute_network_peering_routes_config` terraform to enable `export custom routes` as exemplified on
https://github.com/hashicorp/terraform-provider-google/issues/4778#issuecomment-653267555 instead of using `gcloud`
t commands.

## More information

* [Importing and exporting Routes](https://cloud.google.com/vpc/docs/vpc-peering#importing-exporting-routes)
* [Route types](https://cloud.google.com/vpc/docs/routes#types_of_routes)
* [google_container_cluster resource reference](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster)