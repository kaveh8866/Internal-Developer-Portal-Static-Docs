# OpenTofu layer — OCI provisioning (Stage 2)

Provisions the host that serves the rendered portal: one VCN, one public subnet,
one internet gateway, one hardened security list, and one Always Free eligible
Ampere instance.

**State: written and statically verified, not applied.** `tofu validate` passes
and `tofu plan` reports `6 to add` against a real tenancy. No resource exists yet
— Stage 5 is the first `apply`.

## Layout

```
terraform/
├── versions.tf              root provider pin + backend note
├── main.tf                  local naming/tags, cloud-init, module wiring
├── variables.tf             input contract (identity, network, sizing)
├── outputs.tf               public IP, portal URL, ingress ports, next steps
├── terraform.tfvars.example placeholders only — copy to terraform.tfvars
├── cloud-init.yaml.tftpl    Docker + Compose bootstrap, no secrets
└── modules/
    ├── network/             VCN, IGW, route table, security list, subnet
    └── compute/             A1.Flex instance, Ubuntu image resolution, VNIC
```

## The ingress contract

| Port | Source | Purpose |
| --- | --- | --- |
| 22/tcp | `ssh_allowed_cidr` | Administration (restrict to your egress IP) |
| 80/tcp | `web_allowed_cidr` | Portal — compose publishes container 8080 on host 80 |
| 443/tcp | `web_allowed_cidr` | Portal TLS, once a terminator sits in front |
| 8080 | **never opened** | The container's own port; it must not be reachable directly |

`output.ingress_ports` is derived from the created security list, so it reports
what actually exists rather than what the input claimed. Expect `[22, 80, 443]`.

The default `web_allowed_cidr` is `0.0.0.0/0` so a fresh deployment is
reachable. This is an **internal** portal: narrow it to the office or VPN range
before Stage 5 sign-off, and note the change in the README.

## Commands

```bash
cp terraform.tfvars.example terraform.tfvars   # gitignored, fill in your tenancy
tofu init
tofu fmt -recursive -check
tofu validate
tofu plan                                      # expect: Plan: 6 to add
tofu apply
tofu output connection_endpoints
```

Teardown (Stage 6):

```bash
tofu destroy -auto-approve
tofu state list    # must be empty
```

The portal is stateless — no bucket to empty first, unlike Project 03.

## Portability (AWS / GCP)

| OCI (here) | AWS | GCP |
| --- | --- | --- |
| `oci_core_vcn` | `aws_vpc` | `google_compute_network` |
| `oci_core_internet_gateway` | `aws_internet_gateway` | implicit for a default-route VPC |
| `oci_core_route_table` | `aws_route_table` + `aws_route` | `google_compute_route` |
| `oci_core_security_list` | `aws_security_group` + rules | `google_compute_firewall` |
| `oci_core_subnet` | `aws_subnet` | `google_compute_subnetwork` |
| `oci_core_instance` (`VM.Standard.A1.Flex`) | `aws_instance` (`t4g.small`) | `google_compute_instance` (`e2-micro`) |
| `metadata.user_data` | `user_data` | `metadata_startup_script` |

The module interfaces are provider-neutral: `region`, `vcn_cidr`, `subnet_cidr`,
`instance_shape`, `ssh_public_key`, `web_allowed_cidr`, `ssh_allowed_cidr`. A
port means rewriting the two module bodies and the provider block — the root
module, the variables file and every output keep their names.

## Why one instance and no load balancer

The portal is static HTML served by Nginx at ~13 MB RSS with a 64 MB cap. An
Always Free A1.Flex instance is already more machine than it needs; a load
balancer would add cost, a second failure domain to debug, and no availability
this project can use. If it ever needs HA, the honest answer is a CDN in front
of object storage, not a second VM.

## Known constraints

- **A1 capacity.** AD-1 frequently returns `Out of host capacity`. The module
  takes the first AD by default; pin `availability_domain` to AD-2 in
  `terraform.tfvars` when that happens. Keep the free shape — do not "fix" a
  capacity error by switching to a paid one.
- **No TLS yet.** The container speaks HTTP on 8080 (published as 80). Port 443
  is open for the proxy/terminator that Stage 3–5 will add; until then, browsing
  `https://` on this host fails, and that is expected rather than a bug.
- **Local state.** One operator, one environment. Move to an encrypted remote
  backend before anyone else runs `apply`.
