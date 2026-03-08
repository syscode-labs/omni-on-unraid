# SOP: Terraform Inputs and Operator Environment Variables

## Only values you actually need to add

Add these in `.env`:

- `OMNI_SSH_PUBLIC_KEY_PATH=/absolute/path/to/your/key.pub`
- `OMNI_TAILSCALE_AUTHKEY=tskey-...` (recommended)

`OMNI_LIBVIRT_URI`, `OMNI_BASE_IMAGE_PATH`, and `OMNI_BASE_IMAGE_URL` are pre-populated in template defaults and should be reviewed for your hostnames/paths.

## Critical prerequisite: libvirt availability on Unraid

If you use remote URI like `qemu+ssh://omniops@bookofshadows/system`, Unraid must have VM/libvirt service enabled.

Validation from operator machine:

```bash
virsh -c "$OMNI_LIBVIRT_URI" list --all
```

If this fails with socket/connect errors, enable virtualization/libvirt on Unraid first.

## Variable reference

### `OMNI_LIBVIRT_URI`
- Purpose: Terraform provider endpoint
- Typical value: `qemu+ssh://omniops@bookofshadows/system`

### `OMNI_BASE_IMAGE_PATH`
- Purpose: cloud image path on libvirt host
- Example: `/mnt/user/appdata/omni/images/ubuntu-noble-cloudimg-amd64.qcow2`

### `OMNI_BASE_IMAGE_URL`
- Purpose: source URL used by `infra:prepare-image`

### `OMNI_LIBVIRT_IMAGE_SSH_TARGET`
- Purpose: SSH target for image preparation/check
- Example: `omniops@bookofshadows`

### `OMNI_SSH_PUBLIC_KEY_PATH`
- Purpose: local path to public key used for VM bootstrap

### `OMNI_TAILSCALE_AUTHKEY`
- Purpose: joins VM to tailnet during cloud-init
- Requirement: reusable tagged key for reprovisioning

## Command sequence

```bash
cp templates/omni.env.example .env
# add OMNI_SSH_PUBLIC_KEY_PATH and optional OMNI_TAILSCALE_AUTHKEY

mise run infra:prepare-image
mise run infra:check
mise run infra:init
mise run infra:apply
mise run omni:deploy-remote
```
