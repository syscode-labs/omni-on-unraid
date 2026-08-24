# SOP: Terraform Inputs and Operator Environment Variables

## Only values you actually need to add

Add these in `.env`:

- `OMNI_SSH_PUBLIC_KEY_PATH=/absolute/path/to/your/key.pub`
- `OMNI_TAILSCALE_AUTHKEY=tskey-...` (recommended)

Set `OMNI_LIBVIRT_URI`, `OMNI_BASE_IMAGE_PATH`, and (optionally) `OMNI_LIBVIRT_IMAGE_SSH_TARGET` for your environment.

## Critical prerequisite: libvirt availability on Unraid

If you use remote URI like `qemu+tcp://<libvirt-host>/system`, the libvirt host must have VM/libvirt service enabled.

Validation from operator machine:

```bash
virsh -c "$OMNI_LIBVIRT_URI" list --all
```

If this fails with socket/connect errors, enable virtualization/libvirt on Unraid first.

## Variable reference

### `OMNI_LIBVIRT_URI`
- Purpose: Terraform provider endpoint
- Typical value: `qemu+tcp://<libvirt-host>/system`

### Provider NAT management network
- Purpose: Gives the Omni VM's in-VM libvirt provider a direct path to the
  Unraid host when the LAN address is not reachable from the VM.
- Set `OMNI_PROVIDER_NETWORK_NAME=default` and a fixed
  `OMNI_PROVIDER_NIC_MAC` to attach the second NIC to libvirt's default NAT
  network.
- The default subnet, route metric, and policy-rule priority are
  `192.168.122.0/24`, `200`, and `5000`; override them only when the libvirt
  NAT network differs.
- Configure `OMNI_PROVIDER_LIBVIRT_URI` for the NAT gateway, such as
  `qemu+tcp://192.168.122.1/system`, so the provider reaches host libvirtd
  over the second NIC.

### `OMNI_BASE_IMAGE_PATH`
- Purpose: cloud image path on libvirt host
- Example: `/path/on/libvirt-host/ubuntu-noble-cloudimg-amd64.qcow2`

### `OMNI_BASE_IMAGE_URL`
- Purpose: source URL used by `infra:prepare-image`

### `OMNI_LIBVIRT_IMAGE_SSH_TARGET`
- Purpose: SSH target for image preparation/check
- Example: `<ssh-user>@<libvirt-host>`

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

### `OMNI_DEPLOY_RELAY_IP_PREFIXES`
- Purpose: comma-separated target IP prefixes that require relay via `OMNI_LIBVIRT_IMAGE_SSH_TARGET`
- Default: `192.168.122.`
