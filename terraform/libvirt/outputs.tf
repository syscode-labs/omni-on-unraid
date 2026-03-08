output "vm_name" {
  value = libvirt_domain.vm.name
}

output "vm_network_interfaces" {
  value = libvirt_domain.vm.network_interface
}
