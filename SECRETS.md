# Secrets

Required repository secrets for `.github/workflows/apply.yml`:

- `UNRAID_HOST`: Unraid host (tailnet IP or MagicDNS name)
- `UNRAID_USER`: SSH username on Unraid
- `UNRAID_SSH_PRIVATE_KEY`: private key content (PEM/OpenSSH), multiline secret
- `UNRAID_TARGET_DIR`: absolute path on Unraid where repo is synced

Tailscale credentials (required for CI connectivity):

Preferred:

- `TAILSCALE_OAUTH_CLIENT_ID`
- `TAILSCALE_OAUTH_SECRET`

Fallback:

- `TAILSCALE_AUTHKEY`

## SOP links

- `docs/sops/01-sop-policy.md`
- `docs/sops/10-setup-tailscale-oauth.md`
- `docs/sops/20-apply-omni.md`

## Optional hardening

- Use a dedicated SSH key with command restrictions.
- Use a dedicated deployment user with limited filesystem scope.
