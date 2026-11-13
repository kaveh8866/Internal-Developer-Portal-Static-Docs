# Wires the network and compute modules together.
#
# PORTABILITY (AWS / GCP):
#   OCI VCN + IGW + route table + security list + subnet
#     ≈ AWS  VPC + internet gateway + route table + security group + subnet
#     ≈ GCP  VPC network + default internet route + firewall rule + subnetwork
#   OCI oci_core_instance (VM.Standard.A1.Flex)
#     ≈ AWS  aws_instance (t4g.small / t3.micro free tier)
#     ≈ GCP  google_compute_instance (e2-micro / e2-small free tier)
#
# The ingress contract is 22 from the operator CIDR and 80/443 from the web CIDR
# on every provider; the portal itself listens on 8080 inside the container and
# is published on host port 80 by compose, so no rule has to know about 8080.

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(var.freeform_tags, {
    environment = var.environment
    managed_by  = "opentofu"
    stage       = "2-iac"
  })

  # Cloud-init only prepares the host: Docker, the Compose plugin and an empty
  # application directory. It carries no credential and no repository URL — the
  # portal stack is deployed over SSH, so a leaked user-data blob reveals nothing.
  user_data = base64encode(
    templatefile("${path.module}/cloud-init.yaml.tftpl", {
      project_name = var.project_name
    })
  )
}

module "network" {
  source = "./modules/network"

  # Pin the provider address explicitly. Without this, OpenTofu infers
  # hashicorp/oci for the child module while the root uses oracle/oci, and the
  # two addresses do not share configuration ("did not find a proper
  # configuration for tenancy").
  providers = { oci = oci }

  compartment_id   = var.compartment_ocid
  name_prefix      = local.name_prefix
  vcn_cidr         = var.vcn_cidr
  subnet_cidr      = var.subnet_cidr
  ssh_allowed_cidr = var.ssh_allowed_cidr
  web_allowed_cidr = var.web_allowed_cidr
  vcn_dns_label    = "cloudguardidp"
  subnet_dns_label = "portal"
  freeform_tags    = local.tags
}

module "compute" {
  source = "./modules/compute"

  providers = { oci = oci }

  compartment_id         = var.compartment_ocid
  tenancy_ocid           = var.tenancy_ocid
  name_prefix            = local.name_prefix
  subnet_id              = module.network.subnet_id
  availability_domain    = var.availability_domain
  instance_shape         = var.instance_shape
  instance_ocpus         = var.instance_ocpus
  instance_memory_gbs    = var.instance_memory_gbs
  boot_volume_size_gbs   = var.boot_volume_size_gbs
  ssh_public_key         = var.ssh_public_key
  user_data              = local.user_data
  hostname_label         = var.hostname_label
  image_id               = var.image_id
  image_operating_system = var.image_operating_system
  image_os_version       = var.image_operating_system_version
  freeform_tags          = local.tags
}
