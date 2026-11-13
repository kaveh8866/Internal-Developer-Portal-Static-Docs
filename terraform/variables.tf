# Input contract for the OCI environment.
#
# Anything that differs between operators, clouds or CloudGuard envelopes is a
# variable. Nothing cloud-specific is hard-coded outside terraform.tfvars.
#
# PORTABILITY: on AWS the equivalents are aws_region / vpc_cidr / subnet_cidr /
# instance_type; on GCP, project / region / network / machine_type. Names below
# are provider-neutral where the concept is shared.

# -----------------------------------------------------------------------------
# OCI identity
# -----------------------------------------------------------------------------

variable "tenancy_ocid" {
  description = "OCI tenancy OCID. Also scopes the availability-domain lookup."
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.tenancy\\.", var.tenancy_ocid))
    error_message = "tenancy_ocid must be an OCI tenancy OCID."
  }
}

variable "compartment_ocid" {
  description = "Compartment OCID that owns the VCN and the instance."
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.(compartment|tenancy)\\.", var.compartment_ocid))
    error_message = "compartment_ocid must be an OCI compartment (or tenancy) OCID."
  }
}

variable "region" {
  description = "OCI region identifier, e.g. eu-frankfurt-1."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an OCI region identifier such as eu-frankfurt-1."
  }
}

variable "user_ocid" {
  description = "OCI user OCID for API-key auth. Leave null to read it from the OCI config file."
  type        = string
  default     = null
}

variable "fingerprint" {
  description = "Fingerprint of the API signing key. Leave null to read it from the OCI config file."
  type        = string
  default     = null
}

variable "private_key_path" {
  description = "Path to the OCI API signing private key (outside this repository). Leave null to use the OCI config file."
  type        = string
  default     = null
}

variable "config_file_profile" {
  description = "Profile name inside ~/.oci/config. Set to DEFAULT to authenticate without inline key material."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Naming and tagging
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Short project slug used to prefix every resource name."
  type        = string
  default     = "cloudguard-idp"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with hyphens, 2-31 characters."
  }
}

variable "environment" {
  description = "Environment suffix (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "freeform_tags" {
  description = "Freeform tags applied to every resource (cost tracking / CloudGuard metadata)."
  type        = map(string)
  default = {
    project = "internal-developer-portal-static-docs"
    owner   = "cloudguard"
    tier    = "always-free"
  }
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "vcn_cidr" {
  description = "CIDR block for the VCN. Deliberately disjoint from the other portfolio projects (10.2/10.4) so none of them can collide in one tenancy."
  type        = string
  default     = "10.5.0.0/16"

  validation {
    condition     = can(cidrhost(var.vcn_cidr, 0))
    error_message = "vcn_cidr must be a valid IPv4 CIDR block."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet. Must sit inside vcn_cidr."
  type        = string
  default     = "10.5.1.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "ssh_allowed_cidr" {
  description = "Source CIDR allowed to reach SSH (22). Restrict this to your own address for anything beyond a throwaway environment."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid IPv4 CIDR block."
  }
}

variable "web_allowed_cidr" {
  description = <<-EOT
    Source CIDR allowed to reach the portal on 80 and 443. The default is open so
    a fresh deployment is reachable, but this portal is internal: narrow it to the
    office/VPN range (or the reverse proxy's egress range) before Stage 5
    sign-off. 8080 is never exposed — compose publishes container 8080 on host 80.
  EOT
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.web_allowed_cidr, 0))
    error_message = "web_allowed_cidr must be a valid IPv4 CIDR block."
  }
}

# -----------------------------------------------------------------------------
# Compute
# -----------------------------------------------------------------------------

variable "instance_shape" {
  description = "Compute shape. VM.Standard.A1.Flex is Always Free eligible (up to 4 OCPU / 24 GB across A1 instances)."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "OCPUs for flex shapes. The portal container is capped at 0.25 CPU, so 1 OCPU is generous."
  type        = number
  default     = 1

  validation {
    condition     = var.instance_ocpus >= 1 && var.instance_ocpus <= 4
    error_message = "instance_ocpus must be between 1 and 4 to stay inside the Always Free A1 envelope."
  }
}

variable "instance_memory_gbs" {
  description = "Memory in GB for flex shapes. The portal needs 64 MB; 1 GB is the Always Free floor and leaves room for Docker and image builds."
  type        = number
  default     = 1

  validation {
    condition     = var.instance_memory_gbs >= 1 && var.instance_memory_gbs <= 24
    error_message = "instance_memory_gbs must be between 1 and 24 to stay inside the Always Free A1 envelope."
  }
}

variable "boot_volume_size_gbs" {
  description = "Boot volume size in GB. Holds the OS and the built image."
  type        = number
  default     = 50

  validation {
    condition     = var.boot_volume_size_gbs >= 50
    error_message = "boot_volume_size_gbs must be at least 50 for Ubuntu images on A1 shapes."
  }
}

variable "availability_domain" {
  description = "Availability domain name. Leave null to use the first AD; pin AD-2 if AD-1 reports 'Out of host capacity' for A1 shapes."
  type        = string
  default     = null
}

variable "hostname_label" {
  description = "Hostname label for the VNIC (no hyphens, max 15 characters)."
  type        = string
  default     = "portal"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,14}$", var.hostname_label))
    error_message = "hostname_label must be alphanumeric, start with a letter and be at most 15 characters."
  }
}

variable "ssh_public_key" {
  description = "SSH public key content (not a path, not a private key) injected into the instance metadata."
  type        = string

  validation {
    # Refuses a private key pasted by mistake — the most common OCI provisioning
    # error, and a silent credential leak if it reached state.
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key beginning with ssh-ed25519, ssh-rsa or ecdsa-sha2-*. Never paste a private key."
  }
}

variable "image_id" {
  description = "Pin a specific image OCID. Leave null to resolve the newest Ubuntu build for the shape."
  type        = string
  default     = null
}

variable "image_operating_system" {
  description = "Operating system to resolve when image_id is null."
  type        = string
  default     = "Canonical Ubuntu"
}

variable "image_operating_system_version" {
  description = "OS version to resolve when image_id is null."
  type        = string
  default     = "24.04"
}
