# omni-on-unraid

Self-hosted Omni control plane on Unraid for declarative Talos cluster lifecycle.

## Goal

Run Omni on Unraid with an IaC-first process:

- Terraform + cloud-init provisions the Omni VM
- operator task deploys Omni on that VM

## Repository Layout

- `terraform/libvirt/`: Omni VM infrastructure (libvirt)
- `scripts/`: render/up/down/backup/restore/deploy helpers
- `mise.toml`: operator task entrypoint
- `docs/sops/`: operational SOP set

## IaC Flow (Preferred)

1. Prepare `.env` from template:

```bash
cp templates/omni.env.example .env
```

2. Add only these values in `.env`:

- `OMNI_LIBVIRT_IMAGE_SSH_TARGET`
- `OMNI_SSH_PUBLIC_KEY_PATH`
- `OMNI_TAILSCALE_AUTHKEY` (recommended)

3. Run:

```bash
mise run infra:prepare-image
mise run infra:init
mise run infra:apply
mise run omni:deploy-remote
```

## Notes

- This repo is manual-operator driven (no CI apply workflow).
- Operator-input SOP: `docs/sops/30-terraform-inputs-and-operator-vars.md`
- SSH hardening/persistence SOP: `docs/sops/40-unraid-ssh-operator-hardening.md`
