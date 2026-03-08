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

1. Prepare `.env` from template and fill operator inputs:

```bash
cp templates/omni.env.example .env
```

Required `.env` entries:

- `OMNI_BASE_IMAGE_PATH` (path to cloud image on libvirt host)
- `OMNI_SSH_PUBLIC_KEY_PATH` (your local public key path)

Recommended security entries:

- `OMNI_LIBVIRT_IMAGE_SSH_TARGET` with dedicated restricted Unraid user
  - see `docs/sops/40-unraid-ssh-operator-hardening.md`

Optional bootstrap entries:

- `OMNI_TAILSCALE_AUTHKEY`
- `OMNI_TAILSCALE_HOSTNAME` (defaults to `omni`)

2. Provision VM:

```bash
mise run infra:init
mise run infra:apply
```

3. Deploy Omni to VM:

```bash
mise run omni:deploy-remote
```

By default deploy target resolves from `.env` as:

- `${OMNI_SSH_USER}@${OMNI_TAILSCALE_HOSTNAME}`

Override explicitly with `OMNI_SSH_TARGET` when needed.

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
- Operator-input SOP: `docs/sops/30-terraform-inputs-and-operator-vars.md`
- SSH hardening/persistence SOP: `docs/sops/40-unraid-ssh-operator-hardening.md`
