# SOP: Apply Omni on Unraid

## Purpose

Deploy or update Omni stack on Unraid through the `apply` workflow.

## Prerequisites

- Unraid reachable from tailnet
- Required secrets configured
- `.env` prepared in target directory process

## Steps

1. Dispatch workflow `apply` in GitHub Actions.
2. Wait for completion of:
   - tailnet connection
   - rsync sync
   - remote `render.sh` + `up.sh`

## Validation

1. Check workflow success.
2. SSH to Unraid and verify containers are running.
3. Access Omni UI endpoint and confirm health.

## Rollback

1. Run remote `./scripts/down.sh`.
2. Restore previous backup with `./scripts/restore.sh` if needed.
