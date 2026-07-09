locals {
  fqdn = "${var.hostname}.${var.domain}"
}

# Upload base image from operator machine (only used when base_image_pool is unset)
resource "libvirt_volume" "base" {
  count  = var.base_image_pool == null ? 1 : 0
  name   = "${var.vm_name}-base.qcow2"
  pool   = var.pool_name
  source = var.base_image_path
  format = "qcow2"
}

resource "libvirt_volume" "root" {
  name             = "${var.vm_name}.qcow2"
  pool             = var.pool_name
  base_volume_id   = var.base_image_pool == null ? libvirt_volume.base[0].id : null
  base_volume_pool = var.base_image_pool
  base_volume_name = var.base_image_pool != null ? var.base_image_name : null
  size             = var.disk_size_bytes
}

resource "libvirt_cloudinit_disk" "seed" {
  name = "${var.vm_name}-seed.iso"
  pool = var.pool_name
  user_data = templatefile("${path.module}/cloud-init.yaml.tmpl", {
    hostname           = var.hostname
    fqdn               = local.fqdn
    ssh_username       = var.ssh_username
    ssh_public_key     = var.ssh_public_key
    tailscale_authkey  = var.tailscale_authkey
    tailscale_hostname = var.tailscale_hostname
  })
}

resource "libvirt_domain" "vm" {
  name   = var.vm_name
  memory = var.memory_mb
  vcpu   = var.vcpu

  cpu {
    mode = "host-passthrough"
  }

  cloudinit = libvirt_cloudinit_disk.seed.id

  disk {
    volume_id = libvirt_volume.root.id
  }

  network_interface {
    bridge = var.network_bridge
    mac    = var.vm_mac != "" ? var.vm_mac : null
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "none"
    autoport    = true
  }
}
