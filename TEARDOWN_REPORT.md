# TEARDOWN_REPORT — Stage 6

Recorded 2026-11-13, after the Stage 5 live deployment had been verified end to
end. This is the audit trail: what existed, what was destroyed, and how the "zero
resources" claim was checked **without** trusting the state file.

> **Result: zero billable resources remain.** Instance and boot volume are
> `TERMINATED`, no VCN survives in the compartment, and the public endpoint no
> longer answers. Burn rate is back to $0.

---

## 1. Pre-teardown state

The state file tracked **10 objects**: six managed resources and four data
sources. Managed:

| Resource | Purpose |
| --- | --- |
| `module.network.oci_core_vcn.this` | VCN `10.5.0.0/16` |
| `module.network.oci_core_internet_gateway.this` | egress to the internet |
| `module.network.oci_core_route_table.public` | default route |
| `module.network.oci_core_security_list.public` | ingress 22 / 80 / 443 |
| `module.network.oci_core_subnet.public` | `10.5.1.0/24` |
| `module.compute.oci_core_instance.this` | A1.Flex, 1 OCPU / 1 GB, AD-2 |

Data sources (`oci_core_images`, `oci_identity_availability_domains`,
`oci_core_vnic_attachments`, `oci_core_vnic`) hold no resources and therefore
nothing to destroy.

The portal was confirmed live **immediately before** teardown:
`GET http://152.70.169.194/` → **200**.

## 2. Clean shutdown of the container stack

On the instance, before touching the infrastructure:

```text
docker compose --env-file .env -f docker/docker-compose.yml down
  Network cloudguard-idp_portal-net Removing / Removed
  containers: 0 | running: (none)
```

The local stack had already been stopped at the end of Stage 5
(`cg-portal containers: 0`). Both ends are down, so no container is left running
on a host that is about to disappear.

## 3. `tofu destroy`

Run from `terraform/` after the CloudGuard decision step (destructive action,
explicitly requested):

```text
module.compute.oci_core_instance.this:           Destruction complete after 53s
module.network.oci_core_subnet.public:           Destruction complete after 1s
module.network.oci_core_route_table.public:      Destruction complete after 0s
module.network.oci_core_security_list.public:    Destruction complete after 0s
module.network.oci_core_internet_gateway.this:   Destruction complete after 1s
module.network.oci_core_vcn.this:                Destruction complete after 0s

Destroy complete! Resources: 6 destroyed.
```

Exit code 0. `tofu state list` afterwards: **0 objects**.

The instance took 53 s (termination plus boot-volume delete); the networking
teardown was sub-second once the instance was gone — that ordering matters,
because a VCN cannot be deleted while a VNIC is still attached to it.

## 4. Zero-resource verification (provider-side, not from state)

The state file is a claim; the provider is the evidence. A throwaway read-only
module queried the compartment directly:

| Query | Result |
| --- | --- |
| `oci_core_instances` | `cloudguard-idp-dev-vm (TERMINATED)` — no running instance |
| `oci_core_boot_volumes` (AD-2) | `cloudguard-idp-dev-vm (Boot Volume) (TERMINATED)` — not preserved |
| `oci_core_vcns` | `[]` — **no VCN of any kind remains** |
| `curl http://152.70.169.194/` | `000` (connection refused / timeout) |

`TERMINATED` entries linger in the API for a short while as tombstones; they
carry no cost and cannot be started. The VCN list being empty is the stronger
signal: the entire network was removed, not just the compute.

## 5. What was intentionally **not** destroyed

- The **tenancy IAM policy** created for Project 03's bucket lifecycle — it
  belongs to Project 03 and was already removed during that project's teardown.
  Nothing from Project 05 touched IAM.
- The `cloudguard` bucket observed in the compartment belongs to a different,
  pre-existing project; Project 05 never created storage.

## 6. Local state cleanup

Per the portfolio SOP, state is only removed **after** the provider-side check:

- `terraform.tfstate` and `.tfstate.backup` deleted (they were empty).
- `terraform.tfvars` **kept** — it is gitignored operator configuration, and
  re-deploying with `tofu apply` should not require re-entering the tenancy.
- The throwaway audit module under `.cloudguard/` was deleted after it produced
  the table in §4.

## 7. Cost position

| Resource class | Before teardown | After |
| --- | --- | --- |
| A1.Flex compute (1 OCPU / 1 GB) | 1 instance, Always Free eligible | 0 |
| Boot volume (50 GB) | 1 | 0 |
| VCN / subnet / IGW / route table / security list | 1 each | 0 |
| Object storage | none created | none |
| **Spend rate** | $0 (free-tier) | **$0 (nothing provisioned)** |

It was already $0 in cash terms; the difference is that nothing is now *held*.
A handful of always-free resources left running across five projects is how a
free tier quietly becomes a quota problem later.

## 8. Ready for Stage 7

The repository is back to a clean, undeployed state: `tofu plan` will report
`6 to add` from zero, the docs still carry the Stage 5 measurements, and no
environment has to be "reconciled" before the security audit and release.
