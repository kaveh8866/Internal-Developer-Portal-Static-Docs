# OpenTofu layer (Stage 2 — reserved)

This directory is intentionally empty of `.tf` files at Stage 1. It reserves the
provisioning layer so the repository layout does not change when Stage 2 lands.

## Planned shape

| Module | Resources | Notes |
| --- | --- | --- |
| `modules/network` | VCN, internet gateway, route table, security list, subnet | Ingress 22/tcp from the operator CIDR; **8080 never opened** |
| `modules/compute` | `VM.Standard.A1.Flex`, 1 OCPU / 1 GB, 50 GB boot | ARM Ampere, Always Free envelope; `cloud-init` installs Docker |
| `modules/storage` | none | The portal is stateless: no bucket, no database |

## Design rules for Stage 2

- **The portal port stays closed.** Nginx listens on 8080 inside the instance
  and the source port is never published to the internet; access goes through
  the platform proxy. Opening 8080 "to test it" is how an internal portal ends
  up indexed by a search engine.
- **One instance, no load balancer.** A static site at 8 MiB RSS does not need
  one, and the free tier does not include a meaningful one.
- **Same state discipline as Projects 03 and 04**: state and `terraform.tfvars`
  are gitignored, local only; a `terraform.tfvars.example` carries placeholders.

## Inputs (planned)

| Variable | Purpose |
| --- | --- |
| `tenancy_ocid`, `compartment_ocid` | Where the resources are created |
| `region`, `availability_domain` | Frankfurt AD-2 has A1 capacity when AD-1 does not |
| `ssh_public_key`, `ssh_allowed_cidr` | Bootstrap access |
| `instance_ocpus`, `instance_memory_gbs` | Default 1 / 1, the free-tier floor |
| `portal_port` | Default 8080, bound to loopback in compose |

Nothing here provisions anything yet: `tofu apply` in this directory is a no-op
until Stage 2 adds the modules.
