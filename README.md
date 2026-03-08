# omni-on-unraid

Self-hosted Omni control plane on Unraid for declarative Talos cluster lifecycle.

## Goal

Run Omni on Unraid with an IaC-first process:

- Terraform + cloud-init provisions the Omni VM
- Operator task applies Omni deployment on that VM

## Repository Layout

- `terraform/libvirt/`: Omni VM infrastructure (libvirt)
- `scripts/`: render/up/down/backup/restore/deploy helpers
- `mise.toml`: operator task entrypoint
- `docs/sops/`: operational SOP set

## IaC Flow (Preferred)

1. Set Terraform variables (via `TF_VAR_*` or `terraform.tfvars`)
2. Provision VM:

```bash
mise run infra:init
mise run infra:apply
```

3. Configure deployment target and deploy Omni:

```bash
export OMNI_SSH_TARGET='omni@<vm-ip-or-ts-ip>'
mise run omni:deploy-remote
```

## Local Omni Operations (on deployment target)

```bash
mise run omni:render
mise run omni:up
mise run omni:down
mise run omni:backup
BACKUP=./backups/<file>.tar.gz mise run omni:restore
```

## Notes

- This repo is manual-operator driven (no CI apply workflow).
- If custom domain TLS is required, cert/key paths must be provided in `.env` on target host.
