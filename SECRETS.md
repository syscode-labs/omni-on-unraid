# Secrets

Required repository secrets for `.github/workflows/apply.yml`:

- `UNRAID_HOST`: Unraid host/IP
- `UNRAID_USER`: SSH username on Unraid
- `UNRAID_SSH_PRIVATE_KEY`: private key content (PEM/OpenSSH), multiline secret
- `UNRAID_TARGET_DIR`: absolute path on Unraid where repo is synced

## Optional hardening

- Use a dedicated SSH key with command restrictions.
- Use a dedicated deployment user with limited filesystem scope.
