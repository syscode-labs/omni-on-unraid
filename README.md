# omni-on-unraid

Self-hosted Omni control plane on Unraid for declarative Talos cluster lifecycle.

## IaC Flow (Preferred)

```bash
cp templates/omni.env.example .env
# add OMNI_SSH_PUBLIC_KEY_PATH (+ optional OMNI_TAILSCALE_AUTHKEY)

mise run infra:prepare-image
mise run infra:check
mise run infra:init
mise run infra:apply
mise run omni:deploy-remote
```

## Containerized Tooling (Same Task UX, No Host Toolchain Dependency)

Run the same `mise` tasks via container:

```bash
./scripts/in-container.sh infra:prepare-image
./scripts/in-container.sh infra:check
./scripts/in-container.sh infra:apply
./scripts/in-container.sh omni:deploy-remote
```

Open interactive shell in tooling container:

```bash
./scripts/in-container.sh
```

## Important

- `OMNI_LIBVIRT_URI` must point to your actual libvirt endpoint.
- If using Unraid, VM/libvirt service must be enabled and reachable.
- Full operator details: `docs/sops/`.
- Prereq checklist: `docs/sops/50-prereq-checklist.md`.
