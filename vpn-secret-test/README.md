# VPN Secret Test

I've used the present on this directory to assess how the a VPN pre-shared key is stored on
the Terraform state file. If:
* it is stored in plaintext; or if
* only its hash is stored; or if
* it is stored in any other form (ciphertext, etc.)

## Software Requirements

* Google Cloud SDK
* jq
* Terraform

## Usage

1. Create a `local.auto.tfvars` with the following content:

```hcl-terraform
project_id = "my-project"
pre_shared_key = "verysecurekey"
```

2. Set `google` provider credentials as follows:

```shell script
gcloud auth application-default login
```

3. Deploy VPN tunnel and dependencies with Terraform:
```shell script
terraform init
terraform apply
```

4. Verify that the plaintext password has been recorded on the terraform state file:

```shell script
cat terraform.tfstate | jq '.resources[] | select(.type == "google_compute_vpn_tunnel") | del(.instances[0].private)'
```

Sample output:
```json
{
  "mode": "managed",
  "type": "google_compute_vpn_tunnel",
  "name": "tunnel1",
  "provider": "provider.google",
  "instances": [
    {
      "schema_version": 0,
      "attributes": {
        "creation_timestamp": "2020-07-15T06:26:23.324-07:00",
        "description": "",
        "detailed_status": "Waiting for route configuration.",
        "id": "projects/my-project/regions/europe-west2/vpnTunnels/tunnel1",
        "ike_version": 2,
        "local_traffic_selector": [
          "10.154.0.0/20"
        ],
        "name": "tunnel1",
        "peer_ip": "15.0.0.120",
        "project": "my-project",
        "region": "europe-west2",
        "remote_traffic_selector": [],
        "router": "",
        "self_link": "https://www.googleapis.com/compute/v1/projects/my-project/regions/europe-west2/vpnTunnels/tunnel1",
        "shared_secret": "verysecurekey",
        "shared_secret_hash": "AAKOYwSU4abm-R5o9muLvkjAqsNr",
        "target_vpn_gateway": "https://www.googleapis.com/compute/v1/projects/my-project/regions/europe-west2/targetVpnGateways/vpn1",
        "timeouts": null,
        "tunnel_id": "3291042108896623888"
      },
      "dependencies": [
        "google_compute_address.vpn_static_ip",
        "google_compute_forwarding_rule.fr_esp",
        "google_compute_forwarding_rule.fr_udp4500",
        "google_compute_forwarding_rule.fr_udp500",
        "google_compute_network.network1",
        "google_compute_vpn_gateway.target_gateway"
      ]
    }
  ]
}
```
5. Notice that the JSON path `.instances[0].attributes.shared_secret` displays the password in plaintext.

6. Tear down the infrastructure:
```shell script
terraform destroy
```

7. Revoke Google Application Default Credentials:
```shell script
gcloud auth application-default revoke
```

8. Delete `local.auto.tfvars` and terraform files.
```shell script
rm -r local.auto.tfvars terraform.tfstate* .terraform
```

## Conclusions

The pre-shared key of a GCP VPN Tunnel is stored in plaintext on Terraform's state file.
This is something to take into consideration when managing access to the Terraform state
file as we can see that sensitive information is stored on it.