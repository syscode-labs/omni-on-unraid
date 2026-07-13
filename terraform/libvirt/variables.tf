variable "libvirt_uri" {
  type        = string
  description = "Libvirt URI"
  default     = "qemu:///system"
}

variable "pool_name" {
  type    = string
  default = "default"
}

variable "network_bridge" {
  type        = string
  description = "Host bridge interface for VM NIC (Unraid typically br0; VLAN bridges like br0.50 are supported)"
  default     = "br0"
}

variable "vm_name" {
  type    = string
  default = "omni-vm"
}

variable "base_image_path" {
  type        = string
  description = "Path to Ubuntu cloud image qcow2 on the operator machine (uploaded via libvirt). Only used when base_image_pool is unset."
  default     = null
}

variable "base_image_pool" {
  type        = string
  description = "Libvirt pool that already contains the base image on the host (avoids upload). Takes precedence over base_image_path."
  default     = null
}

variable "base_image_name" {
  type        = string
  description = "Volume name of the base image in base_image_pool."
  default     = "ubuntu-noble-cloudimg-amd64.qcow2"
}

variable "disk_size_bytes" {
  type    = number
  default = 64424509440
}

variable "vcpu" {
  type    = number
  # Omni server + libvirt provider + Caddy + Tailscale are light; the managed
  # Talos nodes run on the Unraid host libvirt, not in this VM.
  default = 2
}

variable "memory_mb" {
  type    = number
  # ponytail: 2 GB floor — Omni + embedded etcd idle ~1–1.5 GB for a small
  # homelab fleet. Bump to 4096 if etcd compaction / large syncs show pressure.
  default = 2048
}

variable "hostname" {
  type    = string
  default = "omni"
}

variable "domain" {
  type    = string
  default = "local"
}

variable "ssh_username" {
  type    = string
  default = "omni"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key to access VM"
}

variable "tailscale_authkey" {
  type        = string
  description = "Tailscale auth key for VM bootstrap"
  default     = ""
}

variable "tailscale_hostname" {
  type    = string
  default = "omni"
}


variable "vm_mac" {
  type        = string
  description = "Optional fixed VM NIC MAC to keep cloud-init netplan match stable across domain replacement"
  default     = ""
}
