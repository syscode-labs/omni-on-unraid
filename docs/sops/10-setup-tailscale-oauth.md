# SOP: Setup Tailscale OAuth for CI

## Purpose

Allow GitHub Actions to join the tailnet securely using OAuth credentials.

## Prerequisites

- Tailscale admin access
- GitHub repo admin access

## Steps

1. Open `https://login.tailscale.com/admin/settings/oauth`.
2. Create/select OAuth client for CI use.
3. Ensure OAuth client has `auth_keys:write` and allowed tag `tag:ci`.
4. Open repository secrets:
   - `https://github.com/syscode-labs/omni-on-unraid/settings/secrets/actions`
5. Set:
   - `TAILSCALE_OAUTH_CLIENT_ID`
   - `TAILSCALE_OAUTH_SECRET`

## Validation

- Run `apply` workflow.
- Confirm step `Connect runner to tailnet (OAuth)` succeeds.

## Rollback

- Rotate OAuth secret in Tailscale and update GitHub secret.
