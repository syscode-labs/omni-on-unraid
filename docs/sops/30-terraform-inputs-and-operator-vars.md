# SOP: Terraform Inputs and Operator Environment Variables

## Policy

Any step that requires manual operator input must be documented with:

- exact variable name
- purpose
- source of truth
- required format
- example value
- validation command

## Variables used in provisioning/deploy flow

### `OMNI_BASE_IMAGE_PATH` (in `.env`)
- Purpose: source cloud image path used by libvirt to create the VM disk
- Source: path on the libvirt host filesystem
- Format: absolute path to qcow2 image
- Example:
  - `/var/lib/libvirt/images/ubuntu-24.04-server-cloudimg-amd64.img`
- Validation:
```bash
ls -lh "$OMNI_BASE_IMAGE_PATH"
```

### `OMNI_SSH_PUBLIC_KEY_PATH` (in `.env`)
- Purpose: path to SSH public key file used for VM bootstrap access
- Source: your operator machine filesystem
- Format: absolute file path to `.pub` file
- Example:
  - `/Users/giovanni/.ssh/syscode.pub`
- Validation:
```bash
test -f "$OMNI_SSH_PUBLIC_KEY_PATH"
cat "$OMNI_SSH_PUBLIC_KEY_PATH"
```

### `OMNI_TAILSCALE_AUTHKEY` (in `.env`, optional)
- Purpose: joins VM to tailnet during cloud-init bootstrap
- Source: Tailscale admin-generated auth key
- Format: key string (`tskey-...`)
- Reusability guidance:
  - Use a **reusable tagged key** for IaC reprovisioning workflows
  - Rotate on schedule and after incidents
- Validation:
```bash
echo "$OMNI_TAILSCALE_AUTHKEY" | grep '^tskey-'
```

### `OMNI_TAILSCALE_HOSTNAME` (in `.env`, optional)
- Purpose: desired Tailscale device hostname for the VM
- Default: `omni`
- Format: DNS-safe short hostname
- Validation:
```bash
echo "$OMNI_TAILSCALE_HOSTNAME" | grep -E '^[a-z0-9-]+$'
```

### `OMNI_SSH_TARGET` (in `.env`, optional override)
- Purpose: explicit SSH destination for remote deploy task
- Format: `user@host`
- If unset: defaults to `${OMNI_SSH_USER}@${OMNI_TAILSCALE_HOSTNAME}`
- Validation:
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 "$OMNI_SSH_TARGET" 'echo ok'
```

## Required operator command sequence

```bash
cp templates/omni.env.example .env
# edit .env with OMNI_BASE_IMAGE_PATH and OMNI_SSH_PUBLIC_KEY_PATH

mise run infra:init
mise run infra:apply

mise run omni:deploy-remote
```

## Audit note

Record after execution:

- date/time
- operator
- VM name
- Terraform apply output reference
- SSH target used
