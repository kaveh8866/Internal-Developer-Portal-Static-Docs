# OCI network module — public VCN with a single public subnet for the portal host.
#
# PORTABILITY — the same five resources on the other free tiers:
#
#   | OCI (here)                | AWS                          | GCP                                |
#   | ------------------------- | ---------------------------- | ---------------------------------- |
#   | oci_core_vcn              | aws_vpc                      | google_compute_network             |
#   | oci_core_internet_gateway | aws_internet_gateway         | (implicit for a default-route VPC) |
#   | oci_core_route_table      | aws_route_table + aws_route   | google_compute_route               |
#   | oci_core_security_list    | aws_security_group + rules    | google_compute_firewall            |
#   | oci_core_subnet           | aws_subnet                   | google_compute_subnetwork          |
#
# The ingress contract below (22 + 80 + 443, each from its own CIDR) maps to one
# security-group rule set on AWS and one firewall rule set on GCP; the variables
# and the exposed IDs do not change across the port.
#
# SECURITY POSTURE
#   Inbound: 22/tcp from ssh_allowed_cidr, 80/tcp and 443/tcp from web_allowed_cidr.
#   Outbound: open (image pulls, OS updates, ACME/OCSP if TLS is added later).
#
#   The portal container itself listens on 8080. That port is *not* opened here:
#   compose publishes it on host port 80 (PORTAL_PORT=80) so the security list
#   stays a three-entry contract and 8080 never becomes reachable directly.

locals {
  # One rule list drives the security list, so the host's exposure is readable in
  # a single place and appears as exactly three rules in the plan.
  ingress_rules = [
    {
      description = "SSH administration"
      port        = 22
      cidr        = var.ssh_allowed_cidr
    },
    {
      description = "Portal HTTP (compose publishes container 8080 on host 80)"
      port        = 80
      cidr        = var.web_allowed_cidr
    },
    {
      description = "Portal HTTPS (TLS terminates at the proxy in front of the container)"
      port        = 443
      cidr        = var.web_allowed_cidr
    },
  ]
}

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  cidr_block     = var.vcn_cidr
  display_name   = "${var.name_prefix}-vcn"
  dns_label      = var.vcn_dns_label
  freeform_tags  = var.freeform_tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-igw"
  enabled        = true
  freeform_tags  = var.freeform_tags
}

# Dedicated route table instead of mutating the VCN's default one: the VCN stays
# reusable and the routing intent is explicit in the plan.
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-public-rt"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
    description       = "Default IPv4 egress to the internet gateway"
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-sl"
  freeform_tags  = var.freeform_tags

  dynamic "ingress_security_rules" {
    for_each = local.ingress_rules

    content {
      protocol    = "6" # TCP
      source      = ingress_security_rules.value.cidr
      source_type = "CIDR_BLOCK"
      description = ingress_security_rules.value.description

      tcp_options {
        min = ingress_security_rules.value.port
        max = ingress_security_rules.value.port
      }
    }
  }

  # Egress stays open: OS updates and image pulls on boot, plus the ability to
  # add an ACME client later without re-planning the network.
  egress_security_rules {
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    description      = "Allow all egress (OS updates, image pulls, TLS/bootstrap traffic)"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = var.subnet_cidr
  display_name               = "${var.name_prefix}-public-subnet"
  dns_label                  = var.subnet_dns_label
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  prohibit_public_ip_on_vnic = false
  freeform_tags              = var.freeform_tags
}
