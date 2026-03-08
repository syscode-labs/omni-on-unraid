# omni-on-unraid

Self-hosted Omni control plane on Unraid for declarative Talos cluster lifecycle.

## Goal

Run Omni on Unraid with a fully declarative process after host prerequisites.

## Scope

- Omni deployment as code (Compose files + env files in git)
- Version-pinned updates
- Backup/restore runbook
- Cluster templates managed in git

## One-Time Host Prerequisites (Manual)

- Enable virtualization in BIOS (`VT-x/AMD-V`)
- Ensure `/dev/kvm` exists on Unraid host
- Ensure Unraid VM/libvirt service is enabled
- Install Docker Compose plugin (or equivalent Unraid App support)

After this point, no clickops are required.

## Declarative Assets

- `templates/omni.env.example`: environment contract
- `templates/compose.yaml`: pinned Omni Compose stack
- `scripts/render.sh`: renders final config from templates
- `scripts/up.sh`: starts stack from rendered config
- `scripts/down.sh`: stops stack
- `scripts/backup.sh`: backup Omni data volumes
- `scripts/restore.sh`: restore Omni data volumes

## Quick Start

1. Copy env template:

```bash
cp templates/omni.env.example .env
```

2. Edit `.env` with your domain/certs/secrets.

3. Render and start:

```bash
./scripts/render.sh
./scripts/up.sh
```

## Upgrade Process

1. Change `OMNI_VERSION` in `.env`
2. Re-render compose
3. Restart stack
4. Verify health and login

## Notes

- For homelab/testing, single-instance Omni is acceptable.
- Do not host Omni inside a cluster managed by the same Omni instance.
