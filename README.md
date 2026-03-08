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

## Containerized Tooling (Stable `mise` Interface)

Run container-backed tasks through `mise`:

```bash
mise run ctr:infra:prepare-image
mise run ctr:infra:check
mise run ctr:infra:apply
mise run ctr:omni:deploy-remote
```

Note: `ctr:infra:prepare-image` and `ctr:infra:check` run on host SSH intentionally; Terraform/apply stays containerized.

Open interactive shell in tooling container:

```bash
mise run ctr:shell
```

## Important

- `OMNI_LIBVIRT_URI` must point to your actual libvirt endpoint.
- `OMNI_LIBVIRT_NETWORK` defaults to `br0` for direct LAN IPs; set to `default` only if you intentionally want NAT.
- With `br0`, your LAN DHCP must lease to VM MACs on that bridge; if not, `ens3` stays without IPv4 and deploy will fail.
- Terraform reads base image from local operator path (`OMNI_LOCAL_BASE_IMAGE_PATH`), then imports into libvirt pool.
- If using Unraid, VM/libvirt service must be enabled and reachable.
- Full operator details: `docs/sops/`.
- Prereq checklist: `docs/sops/50-prereq-checklist.md`.
