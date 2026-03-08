# SOP: Setup Tailscale Bootstrap Credentials

## Status

CI OAuth is not required for this repo (manual operator flow).

For VM bootstrap, provide `TF_VAR_tailscale_authkey` to Terraform cloud-init.

## Steps

1. Create a tagged auth key in Tailscale admin.
2. Export before Terraform apply:

```bash
export TF_VAR_tailscale_authkey='tskey-...'
export TF_VAR_tailscale_hostname='omni'
```

3. Run:

```bash
mise run infra:apply
```
