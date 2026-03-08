# SOP: Unraid SSH Operator Hardening and Persistence

## Purpose

Create a dedicated SSH operator account for this repo automation with restricted scope, and persist the setup across Unraid upgrades/reboots.

## Prerequisites

- Unraid admin access
- Shell access to Unraid host
- Public key for operator machine

## Security objectives

- No reuse of broad/root SSH access for automation
- Restrict account to intended filesystem paths
- Restrict key capabilities (no forwarding/pty)
- Persist account and auth config across reboot/upgrade

## One-time setup on Unraid

1. Create persistent bootstrap directory:

```bash
mkdir -p /mnt/user/appdata/omniops/bootstrap
```

2. Create restricted key file in persistent storage:

```bash
cat >/mnt/user/appdata/omniops/bootstrap/authorized_keys <<'KEY'
no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAA... operator@workstation
KEY
chmod 600 /mnt/user/appdata/omniops/bootstrap/authorized_keys
```

3. Backup current startup script:

```bash
cp /boot/config/go /boot/config/go.bak.$(date +%Y%m%d-%H%M%S)
```

4. Edit `/boot/config/go` and append this idempotent block:

```bash
# --- omniops bootstrap begin ---
if ! id omniops >/dev/null 2>&1; then
  useradd -m -d /mnt/user/appdata/omniops -s /bin/bash omniops
fi
mkdir -p /mnt/user/appdata/omniops/.ssh
install -m 600 /mnt/user/appdata/omniops/bootstrap/authorized_keys /mnt/user/appdata/omniops/.ssh/authorized_keys
chown -R omniops:users /mnt/user/appdata/omniops/.ssh
# --- omniops bootstrap end ---
```

5. Ensure script is executable:

```bash
chmod +x /boot/config/go
```

6. Apply now without reboot (optional immediate apply):

```bash
bash /boot/config/go
```

## Scope boundaries

Allowed paths for `omniops`:

- image path parent for `OMNI_BASE_IMAGE_PATH`
- repo sync target path (`/opt/omni` by default)

Do not grant write access outside these paths.

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

3. Reboot Unraid and verify account/key still present.

## Rollback

- Restore previous `/boot/config/go` backup.
- Remove `omniops` account if needed.
- Rotate SSH key and update bootstrap key file.

## Audit trail note

Record:

- username created
- key fingerprint installed
- `/boot/config/go` change reference
- validation command outputs
