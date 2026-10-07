output "web1_public_ip" {
  value       = yandex_compute_instance.web1.network_interface.0.nat_ip_address
  description = "Public IP of web1"
}

output "bastion_public_ip" {
  value       = yandex_compute_instance.bastion.network_interface.0.nat_ip_address
  description = "Public IP of bastion"
}

output "web1_internal_ip" {
  value       = yandex_compute_instance.web1.network_interface.0.ip_address
  description = "Internal IP of web1"
}

output "bastion_internal_ip" {
  value       = yandex_compute_instance.bastion.network_interface.0.ip_address
  description = "Internal IP of bastion"
}

output "monitor_public_ip" {
  value       = yandex_compute_instance.monitor-node.network_interface.0.nat_ip_address
  description = "Public IP of monitor-node"
}

output "monitor_internal_ip" {
  value       = yandex_compute_instance.monitor-node.network_interface.0.ip_address
  description = "Internal IP of monitor-node"
}
