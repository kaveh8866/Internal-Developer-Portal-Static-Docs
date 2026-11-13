variable "compartment_id" {
  description = "Compartment that owns the VCN and its child resources."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to every resource display name."
  type        = string
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN."
  type        = string

  validation {
    condition     = can(cidrhost(var.vcn_cidr, 0))
    error_message = "vcn_cidr must be a valid IPv4 CIDR block."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "ssh_allowed_cidr" {
  description = "Source CIDR allowed to reach SSH (22/tcp)."
  type        = string

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid IPv4 CIDR block."
  }
}

variable "web_allowed_cidr" {
  description = "Source CIDR allowed to reach the portal (80/tcp, 443/tcp). Narrow this to the office or VPN range for an internal-only portal."
  type        = string

  validation {
    condition     = can(cidrhost(var.web_allowed_cidr, 0))
    error_message = "web_allowed_cidr must be a valid IPv4 CIDR block."
  }
}

variable "vcn_dns_label" {
  description = "DNS label for the VCN (must be a valid DNS label: no hyphens)."
  type        = string
  default     = "cloudguardidp"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,14}$", var.vcn_dns_label))
    error_message = "vcn_dns_label must be alphanumeric, start with a letter and be at most 15 characters."
  }
}

variable "subnet_dns_label" {
  description = "DNS label for the subnet (must be a valid DNS label: no hyphens)."
  type        = string
  default     = "portal"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,14}$", var.subnet_dns_label))
    error_message = "subnet_dns_label must be alphanumeric, start with a letter and be at most 15 characters."
  }
}

variable "freeform_tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
