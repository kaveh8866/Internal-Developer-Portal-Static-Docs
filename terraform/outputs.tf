# Outputs an operator (or the next agent) needs to reach the host and deploy the
# stack. Everything here is public information: IPs and OCIDs, never secrets.

output "instance_public_ip" {
  description = "Public IPv4 address of the portal host. This is the address you SSH to and browse the portal at."
  value       = module.compute.public_ip
}

output "instance_private_ip" {
  description = "Private IPv4 address inside the VCN."
  value       = module.compute.private_ip
}

output "instance_id" {
  description = "OCID of the compute instance."
  value       = module.compute.instance_id
}

output "instance_shape" {
  description = "Shape actually used, including the flex sizing in human-readable form."
  value       = "${var.instance_shape} (${var.instance_ocpus} OCPU / ${var.instance_memory_gbs} GB)"
}

output "availability_domain" {
  description = "Availability domain the instance landed in (pin it in tfvars if A1 capacity is tight)."
  value       = module.compute.availability_domain
}

output "vcn_id" {
  description = "OCID of the VCN."
  value       = module.network.vcn_id
}

output "subnet_id" {
  description = "OCID of the public subnet."
  value       = module.network.subnet_id
}

output "security_list_id" {
  description = "OCID of the security list (ingress: 22, 80, 443/tcp)."
  value       = module.network.security_list_id
}

output "ingress_ports" {
  description = "Inbound TCP ports actually opened by the security list. Expect [22, 80, 443]; 8080 must never appear here."
  value       = module.network.ingress_ports
}

output "portal_url" {
  description = "URL the portal is served on once the stack is deployed on the host."
  value       = "http://${module.compute.public_ip}/"
}

output "connection_endpoints" {
  description = "Copy-paste connection strings for the operator."
  value = {
    ssh   = "ssh ubuntu@${module.compute.public_ip}"
    http  = "http://${module.compute.public_ip}/"
    https = "https://${module.compute.public_ip}/ (only after a TLS terminator is added; the container serves plain HTTP)"
    logs  = "ssh ubuntu@${module.compute.public_ip} 'cd Internal-Developer-Portal-Static-Docs && docker compose --env-file .env -f docker/docker-compose.yml logs -f portal'"
  }
}

output "deploy_next_step" {
  description = "What to run once apply finishes."
  value       = <<-EOT
    1. ssh ubuntu@${module.compute.public_ip}
    2. git clone https://github.com/kaveh8866/Internal-Developer-Portal-Static-Docs.git
    3. cd Internal-Developer-Portal-Static-Docs && cp .env.example .env
       # set PORTAL_BIND_ADDRESS=0.0.0.0 and PORTAL_PORT=80 so the security list rule matches
    4. docker compose --env-file .env -f docker/docker-compose.yml up -d --build
    5. curl -sI http://127.0.0.1/ | head -12   # expect 200 + Content-Security-Policy
  EOT
}
