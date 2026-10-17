output "project_id" {
  description = "Project the PBX lives in (used by scripts/make-inventory.sh)."
  value       = var.project_id
}

output "instance_name" {
  description = "Name of the VM."
  value       = google_compute_instance.pbx.name
}

output "zone" {
  description = "Zone of the VM."
  value       = google_compute_instance.pbx.zone
}

output "external_ip" {
  description = "Static public address. Point your SIP trunk and your DNS here."
  value       = google_compute_address.pbx.address
}

output "internal_ip" {
  description = "Private address inside the VPC."
  value       = google_compute_instance.pbx.network_interface[0].network_ip
}

output "subnet_cidr" {
  description = "Range of the PBX subnet (Asterisk's local_net)."
  value       = google_compute_subnetwork.pbx.ip_cidr_range
}

output "ssh_command" {
  description = "Interactive login through IAP."
  value       = "gcloud compute ssh ${google_compute_instance.pbx.name} --zone ${google_compute_instance.pbx.zone} --project ${var.project_id} --tunnel-through-iap"
}
