# SOP: Terraform Inputs and Operator Environment Variables

## Only values you actually need to add

Add these in `.env`:

- `OMNI_LIBVIRT_IMAGE_SSH_TARGET=omniops@<unraid-host>`
- `OMNI_SSH_PUBLIC_KEY_PATH=/absolute/path/to/your/key.pub`
- `OMNI_TAILSCALE_AUTHKEY=tskey-...` (recommended)

Everything else needed for base image has defaults in `templates/omni.env.example`.

## Variable reference

### `OMNI_LIBVIRT_IMAGE_SSH_TARGET`
- Purpose: SSH target for placing/checking base cloud image on libvirt host
- Format: `user@host`
- Example: `omniops@unraid.wind-bearded.ts.net`
- Security requirement: dedicated restricted user per `docs/sops/40-unraid-ssh-operator-hardening.md`

### `OMNI_SSH_PUBLIC_KEY_PATH`
- Purpose: path to SSH public key file used for VM bootstrap access
- Format: absolute path to `.pub`
- Example: `/Users/giovanni/.ssh/syscode.pub`

### `OMNI_TAILSCALE_AUTHKEY`
- Purpose: joins VM to tailnet during cloud-init bootstrap
- Requirement: use a reusable tagged key for IaC reprovisioning
- Rotation: periodic and on incident

## Command sequence

```bash
cp templates/omni.env.example .env
# add only the 3 values above

mise run infra:prepare-image
mise run infra:init
mise run infra:apply
mise run omni:deploy-remote
```
