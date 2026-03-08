# SOP: Prerequisite Checklist Before `infra:apply`

## Purpose

Validate all runtime prerequisites before Terraform apply, based on real failure modes observed.

## Required checks

### 1) Remote libvirt connectivity

From operator machine:

```bash
virsh -c "$OMNI_LIBVIRT_URI" list --all
```

Must return VM list without connection/socket/channel errors.

### 2) Unraid libvirt listener

On Unraid:

```bash
ss -lntp | grep 16509
```

For TCP flow, listener must not be `127.0.0.1:16509` only.

### 3) Base image exists on libvirt host path

```bash
ssh "$OMNI_LIBVIRT_IMAGE_SSH_TARGET" "ls -lh '$OMNI_BASE_IMAGE_PATH'"
```

If missing:

```bash
mise run infra:prepare-image
```

### 4) Operator SSH access

```bash
ssh "$OMNI_LIBVIRT_IMAGE_SSH_TARGET" 'echo ok'
```

### 5) Local toolchain

If running on host:

- `terraform`
- `virsh`
- `mkisofs` (or `genisoimage`)

If avoiding host deps, run via container wrapper:

```bash
./scripts/in-container.sh infra:apply
```

## Recommended run order

```bash
mise run infra:prepare-image
mise run infra:check
mise run infra:init
mise run infra:apply
mise run omni:deploy-remote
```
