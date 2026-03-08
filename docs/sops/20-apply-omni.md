# SOP: Provision and Apply Omni (IaC)

## Purpose

Provision Omni VM with Terraform and deploy Omni on it using repository automation tasks.

## Prerequisites

- Unraid/libvirt reachable from operator machine
- Terraform and mise installed
- SSH key pair available
- Tailscale auth key available for bootstrap (optional but recommended)

## Terraform variables

Set at least:

- `TF_VAR_base_image_path` (Ubuntu cloud image path on libvirt host)
- `TF_VAR_ssh_public_key`
- `TF_VAR_tailscale_authkey` (optional)
- `TF_VAR_tailscale_hostname` (recommended, e.g. `omni`)

## Steps

1. Provision VM:

```bash
mise run infra:init
mise run infra:apply
```

2. Identify VM address (libvirt lease or Tailscale IP).
3. Deploy Omni to VM:

```bash
export OMNI_SSH_TARGET='omni@<vm-ip-or-ts-ip>'
mise run omni:deploy-remote
```

## Validation

- VM is reachable via SSH
- `tailscale status` on VM shows connected (if enabled)
- Omni container is running and healthy
- Omni endpoint responds

## Rollback

```bash
mise run infra:destroy
```
