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
- Purpose: cloud image path Terraform references on libvirt host
- Format: absolute path
- Example:
  - `/var/lib/libvirt/images/ubuntu-noble-cloudimg-amd64.qcow2`
- Validation:
```bash
mise run infra:prepare-image
mise run infra:check
```

### `OMNI_BASE_IMAGE_URL` (in `.env`)
- Purpose: download source for automatic image preparation
- Default:
  - `https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img`

### `OMNI_LIBVIRT_IMAGE_SSH_TARGET` (in `.env`, recommended)
- Purpose: SSH target to place/check image on libvirt host
- Format: `user@host`
- Example:
  - `omniops@unraid.tailnet.ts.net`
- Security requirement:
  - use dedicated restricted account (see `docs/sops/40-unraid-ssh-operator-hardening.md`)

### `OMNI_SSH_PUBLIC_KEY_PATH` (in `.env`)
- Purpose: path to SSH public key file used for VM bootstrap access
- Format: absolute path to `.pub`
- Example:
  - `/Users/giovanni/.ssh/syscode.pub`

### `OMNI_TAILSCALE_AUTHKEY` (in `.env`, optional)
- Purpose: joins VM to tailnet during cloud-init bootstrap
- Reusability guidance:
  - use a reusable tagged key for IaC reprovisioning
  - rotate periodically

### `OMNI_TAILSCALE_HOSTNAME` (in `.env`, optional)
- Purpose: desired Tailscale device hostname for VM
- Default: `omni`

### `OMNI_SSH_TARGET` (in `.env`, optional override)
- Purpose: explicit SSH destination for remote deploy task
- If unset: defaults to `${OMNI_SSH_USER}@${OMNI_TAILSCALE_HOSTNAME}`

## Required operator command sequence

```bash
cp templates/omni.env.example .env
# edit .env

mise run infra:prepare-image
mise run infra:init
mise run infra:apply

mise run omni:deploy-remote
```
