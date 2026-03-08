# SOP: Apply Omni on Unraid (Manual)

## Purpose

Deploy or update Omni stack on Unraid without CI.

## Prerequisites

- SSH access to Unraid host
- `.env` values ready
- required host prerequisites already satisfied

## Steps (mise)

1. Prepare env file:

```bash
cp templates/omni.env.example .env
```

2. Edit `.env` with domain/cert/secrets.
3. Run prerequisite checks:

```bash
mise run omni:doctor
```

4. Apply stack:

```bash
mise run omni:apply
```

## Validation

1. Check Omni containers are healthy.
2. Reach Omni UI/API endpoint.
3. Confirm logs show successful startup.

## Rollback

1. Stop stack:

```bash
mise run omni:down
```

2. Restore backup if needed:

```bash
BACKUP=./backups/<file>.tar.gz mise run omni:restore
```
