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

## Containerized Tooling (Single `mise` Interface)

Run container-backed tasks through `mise`:

```bash
mise run ctr:infra:prepare-image
mise run ctr:infra:check
mise run ctr:infra:apply
mise run ctr:omni:deploy-remote
```

Open interactive shell in tooling container:

```bash
mise run ctr:shell
```

## Important

- `OMNI_LIBVIRT_URI` must point to your actual libvirt endpoint.
- If using Unraid, VM/libvirt service must be enabled and reachable.
- Full operator details: `docs/sops/`.
- Prereq checklist: `docs/sops/50-prereq-checklist.md`.
