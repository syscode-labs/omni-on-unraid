# SOP: Unraid SSH Operator Hardening and Persistence

## Purpose

Create a dedicated SSH operator account for this repo automation with restricted scope, and persist the setup across Unraid upgrades/reboots.

## Prerequisites

- Unraid admin access
- Shell access to Unraid host
- Public keys for operator machine

## Security objectives

- No reuse of broad/root SSH access for automation
- Restrict account to intended filesystem paths
- Restrict key capabilities (no forwarding/pty)
- Persist account and auth config across reboot/upgrade

## Account model

Use one dedicated account, for example:

- username: `omniops`
- group: minimal required group only
- home: persistent share path (for example `/mnt/user/appdata/omniops`)

## Authorized key restrictions

In `~omniops/.ssh/authorized_keys`, use key options:

```text
no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAA... operator@workstation
```

If you need command restrictions, use a forced command wrapper and implement allowlist checks.

## Scope boundaries

Allowed paths:

- image path parent for `OMNI_BASE_IMAGE_PATH`
- repo sync target path (`/opt/omni` by default)

Do not grant write access outside these paths.

## Persistence on Unraid

Unraid root filesystem changes may not persist unless captured in startup scripts/config.

Recommended pattern:

1. Keep desired user SSH config as files in an Unraid persistent share (for example `/mnt/user/appdata/omniops/bootstrap/`).
2. Add idempotent apply logic in Unraid startup script (`/boot/config/go`) to:
   - ensure user exists
   - ensure `.ssh` directory and permissions
   - install/update `authorized_keys` from persistent source
   - enforce ownership and mode

Example `go` snippet shape (adapt paths/user for your host):

```bash
# idempotent account/bootstrap placeholder
if ! id omniops >/dev/null 2>&1; then
  useradd -m -d /mnt/user/appdata/omniops -s /bin/bash omniops
fi
mkdir -p /mnt/user/appdata/omniops/.ssh
install -m 600 /mnt/user/appdata/omniops/bootstrap/authorized_keys /mnt/user/appdata/omniops/.ssh/authorized_keys
chown -R omniops:users /mnt/user/appdata/omniops/.ssh
```

## Repo variable mapping

Set in `.env`:

- `OMNI_LIBVIRT_IMAGE_SSH_TARGET=omniops@<unraid-host>`
- optional deploy override:
  - `OMNI_SSH_TARGET=omni@<omni-vm-host>`

## Validation

1. Verify restricted login:

```bash
ssh omniops@<unraid-host> 'id && whoami'
```

2. Verify image preparation path works:

```bash
mise run infra:prepare-image
```

3. Verify no unintended SSH capabilities (pty/forwarding) are available.

## Rollback

- Remove restricted key entry and disable account if compromised.
- Rotate SSH key pair and reapply bootstrap from persistent source.

## Audit trail note

Record:

- username created
- key fingerprint installed
- startup persistence method/path
- validation command outputs
