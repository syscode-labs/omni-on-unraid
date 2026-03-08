# SOP: Provision and Apply Omni (IaC)

## Purpose

Provision Omni VM with Terraform and deploy Omni on it using repository automation tasks.

## Prerequisites

- Unraid/libvirt reachable from operator machine
- Terraform and mise installed
- `.env` filled from template

For all manual input variables, see:

- `docs/sops/30-terraform-inputs-and-operator-vars.md`

## Steps

1. Validate infra inputs:

```bash
mise run infra:check
```

2. Provision VM:

```bash
mise run infra:init
mise run infra:apply
```

3. Deploy Omni to VM:

```bash
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
