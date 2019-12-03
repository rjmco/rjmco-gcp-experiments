# Use of Cloud SQL Proxy's and it's special MySQL account

The code and documentation present on this folder presents a walk-through on how to create a private networking environment containing a Cloud SQL MySQL instance and a client GCE instance and using Cloud SQL Proxy to facilitate the connection between the MySQL client application (running on the GCE instance) and the MySQL server.

This walk-through leverages Terraform for infrastructure deployment and Packer for creating a boot disk image for the GCE instance.

The walk-through also showcases the benefits of using Cloud SQL Proxy (over making the connection directly) such as:
* Allowing the MySQL client configuration to be delegated to the infrastructure team by allowing it to be set dynamically by Terraform and relayed to Cloud SQL proxy through the GCE instance's metadata;
* Allowing to easily divert traffic from SQL applications running on the GCE instance by changing a metadata item and without requiring any application restart;
* Guaranteeing all traffic exiting the GCE instance and ingressing into the Cloud SQL instance to be encrypted in-transit.
* Delegating authentication to Google's IAM and Cloud SQL Proxy releasing the application owner's from having to manage secret storage and password lifecycle management (only available on the MySQL flavour);
* Easing troubleshooting network issues by logging connection errors to Stackdriver;

## Folder Structure

The root folder contains a `README.md` file and is expected to include a `local_var.json` variable file which is populated during the walk-through instructions.

The `images` folder contains a symbolic link to the `local_vars.json` file on the root directory and packer's configuration.
The `images/files` folder contains a systemD service unit file which is used to manage Cloud SQL Proxy as a service on the GCE instance.

The `infrastructure` folder contains a symbolic link to the `local_vars.json` file on the root directory and the Terraform code to spin-up the whole infrastructure on GCP.

## Preparation steps

Before following the walk-through, you will need to create a GCP project, set-up it's billing and activate the Compute API.

To activate the Compute Engine API you can use the following `gcloud` command (replace `PROJECT_ID` with your project name):

```bash
gcloud --project PROJECT_ID services enable compute.googleapis.com
```

You will also need to install `packer` and `terraform`. 

For reference, the walk-through guide has been tested with the following software and version:

| Software Package | Version |
|---|---|
| `packer` | `1.4.5` |
| `terraform` | `0.12.16` |
| `terraform-provider-google` | `3.0.0-beta.1` |

## Deployment Walk-through

The deployment walk-through is split into 3 steps.
A first step to create a variable file used throughout the rest of the guide.
A second step to create a GCE boot disk image with MySQL client and Cloud SQL Proxy installed.
A third and final step to deploy the whole infrastructure.

### Create a common variable file

1. Create file named `local_vars.json` on the same directory as this `README.md` file with the follwing structure:

```json
{
  "project_id": "my-test-project",
  "region": "us-central1",
  "zone": "us-central1-a"
}
```

2. Customize the values on the `local_vars.json` to suite your environment.

### Create a GCE boot image w/ a MySQL client and Cloud SQL Proxy

1. Change directory to the `images` folder.

```bash
cd images
```

2. Execute `packer` to build the image has configured on the `cloudsqlproxyclient.json` file and with the variable values defined on the preparation step:

```bash
packer build -var-file=cloudsqlproxyclient_vars.json cloudsqlproxyclient.json
```

The above will create a GCE instance on the project's `default` VPC, install Cloud SQL Proxy and a MySQL client. It will also upload and enable the `cloud-sql-proxy.service` unit file. This unit file configures systemD to keep Cloud SQL Proxy running and configured to inspect an instance metadata key. More information on the exact software deployment steps can be found on the [cloudsqlproxyclient.json] file under the `provisioner` section.
Once the software is installed and configured `packer` will delete the instance create an image named `cloudsqlproxyclient-[date_and_time]` under a `cloudsqlproxy-client` image family on thee project set on the `local_vars.json` file.

You can list the image create with the following `gcloud` command (replace `PROJECT_ID` with your project name):

```bash
gcloud --project PROJECT_ID compute images list --no-standard-images
```

### Deploy the demonstration infrastructure

The demonstration environment consists of the following components:

| Component Type | Notes |
|---|---|
| `module.project-services` | This enables API services on the project (4 APIs are enabled) |
| `google_compute_network` | A custom VPC network to host the private GCE instance where the MySQL client is run from |
| `google_compute_subnetwork` | A subnetwork to host the private GCE instance |
| `google_compute_global_address` | A RFC1918 CIDR range required for the VPC peering connection between the VPC and Google's Services (tenant projects) |
| `google_service_networking_connection` | This instantiates the VPC Peering which enables *Private Service Access* to Cloud SQL instance |
| `google_compute_firewall` | A firewall rule to allow SSH access to the GCE instance through a Identity-Aware Proxy (IAP) tunnel |
| `google_service_account` | A service account used as the GCE instance's default service account |
| `google_project_iam_binding` | This gives the service account the necessary roles which allow the Cloud SQL Proxy running on the instance to interact with the Cloud SQL API and connect to the MYSQL instance. They also allow the instance to push monitoring metrics and log entries to Stackdriver |
| `google_compute_disk` | The GCE instance's boot disk created from a `cloudsqlproxy-client` image |
| `google_compute_instance` | A GCE instance to run Cloud SQL Proxy and the MySQL client on - and with them - test the connection to the Cloud SQL instance |
| `google_sql_database_instance` | The private Cloud SQL instance |
| `google_sql_user` | A special MySQL instance account with the format `[NAME]@cloudsqlproxy~[IP_ADDRESS]` which when used informs Cloud SQL Proxy to handle the authentication process |

To deploy the environment:

1. First leave the `images/` folder and enter the `infrastructure` folder:

```bash
cd ../infrastructure
```

2. Execute `terraform` has configured on the `main.tf` file and using the variables declared on the `local_vars.json` file on the parent directory:

```bash
terraform init
terraform apply
```

## Demonstrating Cloud SQL Proxy features

* On the GCP web console go to the Cloud SQL area and notice a new instance with a name in the format `terraform-1234567891234567890`. Click on it to see its details page.
  * notice on the connections tab that the instance does not have a public IP and on the *SSL* section that it will only accept SSL connections;
  * notice on the users tab that a user named `myapp` with a host name `cloudsqlproxy~192.168.0.2`. This is a special user account that only allows connections from a user named `myapp` incoming from a Cloud SQL Proxy client running on a system (VM or container) with IP `192.168.0.2`.

* On the GCP web console go to the VM instances area under Compute Engine and find an instance named `cloudsqlproxy-i0`. Click on it to see its details page:
  * notice on the Custom metadata section a metadata key called `cloudsql-instances` with a value similar to `my-test-project:us-central1:terraform-1234567891234567890=tcp:3306`. The Cloud SQL Proxy client running on the GCE instance will watch this key for updates and use its value as its configuration.
  * It this particular example it will expose a Cloud SQL instance named `terraform-1234567891234567890` hosted on the `us-central1` region and on the `my-test-project` project on port `3306` of the instance's loop-back network interface (that's what the `=tcp:3306` stands for).
  * More then one Cloud SQL instance can be exposed by Cloud SQL Proxy. To achieve this concatenate each configuration string separated by commas (make sure the ports differ).

* SSH into the `cloudsqlproxy` with `gcloud` using an IAP tunnel with a command similar to the following (replace `PROJECT_ID` with your project name):

```bash
gcloud --project PROJECT_ID compute ssh cloudsqlproxy-i0 --zone us-central1-a --tunnel-through-iap
```

* Notice that systemD has automatically started Cloud SQL Proxy:

```bash
sudo systemctl status cloud-sql-proxy.service
```

Here's an example output:

```
● cloud-sql-proxy.service - Connecting MySQL Client from Compute Engine using the Cloud SQL Proxy
   Loaded: loaded (/etc/systemd/system/cloud-sql-proxy.service; enabled; vendor preset: enabled)
   Active: active (running) since Tue 2019-12-03 09:17:30 UTC; 8h ago
     Docs: https://cloud.google.com/sql/docs/mysql/connect-compute-engine
 Main PID: 627 (cloud_sql_proxy)
    Tasks: 7 (limit: 4915)
   CGroup: /system.slice/cloud-sql-proxy.service
           └─627 /usr/local/bin/cloud_sql_proxy -dir=/var/run/cloud-sql-proxy -instances_metadata=instance/attributes/cloudsql-instances

Dec 03 09:17:30 cloudsqlproxy-i0 systemd[1]: Started Connecting MySQL Client from Compute Engine using the Cloud SQL Proxy.
Dec 03 09:17:30 cloudsqlproxy-i0 cloud_sql_proxy[627]: 2019/12/03 09:17:30 Rlimits for file descriptors set to {&{8500 8500}}
Dec 03 09:17:35 cloudsqlproxy-i0 cloud_sql_proxy[627]: 2019/12/03 09:17:35 Ready for new connections
Dec 03 09:17:35 cloudsqlproxy-i0 cloud_sql_proxy[627]: 2019/12/03 09:17:35 Listening on 127.0.0.1:3306 for my-test-project:us-central1:terraform-1234567891234567890
```

* Notice that the last line of the log tells us that Cloud SQL Proxy is listening on `127.0.0.1:3306`.
* Notice that the executed command by systemD to start Cloud SQL Proxy is `/usr/local/bin/cloud_sql_proxy -dir=/var/run/cloud-sql-proxy -instances_metadata=instance/attributes/cloudsql-instances`.
* The `-instance_metadata` parameter which is part of the command states which metadata key Cloud SQL Proxy should read and keep an eye for configuration changes.

You can extract the same configuration from the metadata service yourself with a `curl` command with such as the following:

```bash
curl -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/attributes/cloudsql-instances
```

* Finally use the `mysql` client to connect to the instance without requiring a password:

```bash
mysql -h 127.0.0.1 -u myapp
```

### Bonus exploration

* Try to create another instance with the `cloudsqlproxy-client` image and the same `cloudsql-instances` metadata key and see that you can't connect to the Cloud SQL instance - this is because the IP differs from the account's host name configured on the MySQL instance);
* Go to instance's logs on Stackdriver and try to find the Cloud SQL Proxy logs.

## Clean-up tasks

1. Delete the infrastructure spun-up by `terraform` with a `destroy`:

```bash
terraform destroy
```

2. Delete the image(s) created by `packer` with a command such as the following (don't forget to replace `PROJECT_ID` twice):

```bash
gcloud --project PROJECT_ID compute images delete $(gcloud --project PROJECT_ID compute images list --filter=family=cloudsqlproxy-client --format='value(self_link)')
```
