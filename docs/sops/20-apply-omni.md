# SOP: Apply Omni on Unraid (Manual)

## Purpose

Deploy or update Omni stack on Unraid without CI.

## Prerequisites

- SSH access to Unraid host
- `.env` values ready
- required host prerequisites already satisfied

## Steps

1. Sync or clone repo on target environment.
2. Prepare env file:

```bash
cp templates/omni.env.example .env
```

3. Edit `.env` with domain/cert/secrets.
4. Render deployment files:

```bash
./scripts/render.sh
```

5. Apply stack:

```bash
./scripts/up.sh
```

## Validation

1. Check Omni containers are healthy.
2. Reach Omni UI/API endpoint.
3. Confirm logs show successful startup.

## Rollback

1. Stop stack:

```bash
./scripts/down.sh
```

2. Restore backup if needed:

```bash
./scripts/restore.sh
```
