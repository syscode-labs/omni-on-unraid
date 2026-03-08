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

### `TF_VAR_base_image_path`
- Purpose: source cloud image path used by libvirt to create the VM disk
- Source: path on the libvirt host filesystem
- Format: absolute path to qcow2 image
- Example:
  - `/var/lib/libvirt/images/ubuntu-24.04-server-cloudimg-amd64.img`
- Validation:
```bash
ls -lh "$TF_VAR_base_image_path"
```

### `TF_VAR_ssh_public_key`
- Purpose: bootstrap SSH access to the provisioned VM
- Source: your operator SSH public key
- Format: single-line OpenSSH public key
- Example:
  - `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... operator@host`
- Validation:
```bash
echo "$TF_VAR_ssh_public_key" | grep -E '^(ssh-ed25519|ssh-rsa) '
```

### `TF_VAR_tailscale_authkey`
- Purpose: joins the VM to tailnet during cloud-init bootstrap
- Source: Tailscale admin-generated auth key
- Format: key string (`tskey-...`)
- Notes: treat as secret; rotate if exposed
- Validation:
```bash
echo "$TF_VAR_tailscale_authkey" | grep '^tskey-'
```

### `TF_VAR_tailscale_hostname`
- Purpose: desired Tailscale device hostname for the VM
- Source: operator naming choice
- Format: DNS-safe short hostname
- Example:
  - `omni`
- Validation:
```bash
echo "$TF_VAR_tailscale_hostname" | grep -E '^[a-z0-9-]+$'
```

### `OMNI_SSH_TARGET`
- Purpose: SSH destination used by `mise run omni:deploy-remote`
- Source: VM reachable address after provisioning (libvirt IP or Tailscale IP)
- Format: `user@host`
- Example:
  - `omni@100.101.102.103`
- Validation:
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 "$OMNI_SSH_TARGET" 'echo ok'
```

## Required operator command sequence

```bash
export TF_VAR_base_image_path='...'
export TF_VAR_ssh_public_key='ssh-ed25519 AAAA...'
export TF_VAR_tailscale_authkey='tskey-...'
export TF_VAR_tailscale_hostname='omni'

mise run infra:init
mise run infra:apply

export OMNI_SSH_TARGET='omni@<vm-ip-or-tailscale-ip>'
mise run omni:deploy-remote
```

## Audit note

Record after execution:

- date/time
- operator
- VM name
- Terraform apply output reference
- SSH target used
