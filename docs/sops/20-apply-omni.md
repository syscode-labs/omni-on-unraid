# SOP: Provision and Apply Omni (IaC)

## Purpose

Provision Omni VM with Terraform and deploy Omni on it using repository automation tasks.

## Prerequisites

- Unraid/libvirt reachable from operator machine
- Terraform and mise installed
- SSH key pair available
- Tailscale auth key available for bootstrap (optional but recommended)

For all manual input variables, see:

- `docs/sops/30-terraform-inputs-and-operator-vars.md`

## Steps

1. Export required variables.
2. Provision VM:

```bash
mise run infra:init
mise run infra:apply
```

3. Identify VM address (libvirt lease or Tailscale IP).
4. Deploy Omni to VM:

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
