locals {
  fqdn = "${var.hostname}.${var.domain}"
}

resource "libvirt_volume" "base" {
  name   = "${var.vm_name}-base.qcow2"
  pool   = var.pool_name
  source = var.base_image_path
  format = "qcow2"
}

resource "libvirt_volume" "root" {
  name           = "${var.vm_name}.qcow2"
  pool           = var.pool_name
  base_volume_id = libvirt_volume.base.id
  size           = var.disk_size_bytes
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
