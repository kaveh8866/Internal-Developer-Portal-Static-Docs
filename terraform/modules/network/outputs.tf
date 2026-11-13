output "vcn_id" {
  description = "OCID of the VCN."
  value       = oci_core_vcn.this.id
}

output "subnet_id" {
  description = "OCID of the public subnet."
  value       = oci_core_subnet.public.id
}

output "security_list_id" {
  description = "OCID of the security list (ingress: 22, 80, 443/tcp)."
  value       = oci_core_security_list.public.id
}

output "internet_gateway_id" {
  description = "OCID of the internet gateway."
  value       = oci_core_internet_gateway.this.id
}

output "route_table_id" {
  description = "OCID of the public route table."
  value       = oci_core_route_table.public.id
}

# Derived from the created security list rather than from the input list, so an
# operator (or a test) reads the host's actual exposed surface. Expect [22, 80, 443].
output "ingress_ports" {
  description = "Inbound TCP ports the security list actually allows."
  value       = [for rule in oci_core_security_list.public.ingress_security_rules : rule.tcp_options[0].min]
}

output "egress_cidrs" {
  description = "Destinations the security list actually permits outbound traffic to."
  value       = [for rule in oci_core_security_list.public.egress_security_rules : rule.destination]
}
