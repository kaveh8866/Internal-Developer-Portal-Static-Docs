# Internal Developer Portal — OCI environment (Stage 2)
#
# Root module. Provisions the network and the single host that serves the Stage 1
# portal image. There is deliberately no storage module: the portal is a rendered
# static site, so it needs no bucket, no managed database and no persistent disk
# beyond the boot volume.
#
# PORTABILITY (AWS / GCP): every resource here has a 1:1 equivalent — see the
# mapping tables at the top of modules/network/main.tf and
# modules/compute/main.tf. Variable names are provider-neutral wherever the
# concept is shared (region, vcn_cidr/subnet_cidr, ssh_public_key,
# instance_shape). Only the provider block and the module bodies change.

terraform {
  # OpenTofu 1.6+ and Terraform 1.6+ both satisfy this configuration.
  required_version = ">= 1.6.0"

  required_providers {
    oci = {
      source = "oracle/oci"
      # 6.x is the current major line; allow newer majors only after testing.
      version = ">= 6.20.0, < 8.0.0"
    }
  }

  # State is local for Stage 2: one operator, one environment.
  # Move to an encrypted remote backend before any shared use — state holds
  # resource identifiers and is never committed (see ../.gitignore).
  #
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "internal-developer-portal/oci.tfstate"
  #   region = "eu-frankfurt-1"
  # }
  #
  # AWS/GCP port: `backend "s3"` works there too, or `backend "gcs"` on GCP.
  # Nothing else in this configuration is state-backend-specific.
}

provider "oci" {
  region = var.region

  # API-key authentication. Every value comes from variables (or from
  # ~/.oci/config when left null) — never from a file in this repository.
  tenancy_ocid        = var.tenancy_ocid
  user_ocid           = var.user_ocid
  fingerprint         = var.fingerprint
  private_key_path    = var.private_key_path
  config_file_profile = var.config_file_profile
}
