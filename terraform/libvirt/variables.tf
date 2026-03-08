variable "libvirt_uri" {
  type        = string
  description = "Libvirt URI"
  default     = "qemu:///system"
}

variable "pool_name" {
  type    = string
  default = "default"
}

variable "network_name" {
  type    = string
  default = "default"
}

variable "vm_name" {
  type    = string
  default = "omni-vm"
}

variable "base_image_path" {
  type        = string
  description = "Path to Ubuntu cloud image qcow2 available on libvirt host"
}

variable "disk_size_bytes" {
  type    = number
  default = 64424509440
}

variable "vcpu" {
  type    = number
  default = 4
}

variable "memory_mb" {
  type    = number
  default = 8192
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
