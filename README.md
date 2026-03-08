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
- `scripts/render.sh`: fetches pinned upstream Omni deploy assets
- `scripts/up.sh`: starts stack from rendered config
- `scripts/down.sh`: stops stack
- `scripts/backup.sh`: backup Omni data volumes
- `scripts/restore.sh`: restore Omni data volumes
- `mise.toml`: local operator task entrypoint
- `docs/sops/`: operational SOP set

## Manual Apply (Preferred: mise)

```bash
cp templates/omni.env.example .env
# edit .env
mise run omni:doctor
mise run omni:apply
```

Equivalent make flow:

```bash
make doctor
make apply
```

## Common Operations

```bash
mise run omni:backup
BACKUP=./backups/omni-data-YYYYmmdd-HHMMSS.tar.gz mise run omni:restore
mise run omni:down
mise run omni:up
```

## Upgrade Process

1. Change `OMNI_VERSION` in `.env`
2. Re-render compose (`mise run omni:render`)
3. Restart stack (`mise run omni:down && mise run omni:up`)
4. Verify health and login

## Notes

- For homelab/testing, single-instance Omni is acceptable.
- Do not host Omni inside a cluster managed by the same Omni instance.
