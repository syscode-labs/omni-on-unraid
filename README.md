# omni-on-unraid

Self-hosted Omni control plane on Unraid for declarative Talos cluster lifecycle.

## Talos Cluster Provisioning Through Omni

Current answer: this repo can fully provision Talos machines through Omni only when
an Omni infrastructure provider is configured for the target platform. For Unraid,
use the Omni libvirt infrastructure provider. Without that provider, Omni can create
clusters only from already registered machines.

Omni-only lab path with the official libvirt infra provider:

```bash
devbox shell
# or: nix develop .#omni

# Create provider credentials in Omni and save them in ignored .env.
# Example:
# omnictl serviceaccount create infra-provider:libvirt --role InfraProvider --use-user-role=false
# Then set OMNI_ENDPOINT, OMNI_SERVICE_ACCOUNT_KEY, OMNI_PROVIDER_LIBVIRT_URI,
# and OMNI_PROVIDER_SSH_KEY_FILE in .env.

make provider
make provider-status
make mc
make cluster
```

Install the operator TUI if you do not want to remember targets:

```bash
make install
omni-on-unraid
```

Or run it without installing:

```bash
make tui
```

Package/install options:

```bash
nix run .#omni-on-unraid
brew install --cask syscode-labs/public/omni-on-unraid
```

Releases are CI-driven with Release Please and GoReleaser. Use Conventional
Commits (`fix:`, `feat:`, `feat!:`) to drive patch/minor/major release PRs.
Release and packaging details: `docs/packaging.md`.

Default cluster shape is in `omni/cluster-templates/unraid-lab.yaml`: three
schedulable control-plane nodes, no workers. UI-selectable MachineClasses live
in `omni/machine-classes/` as `unraid-cp` and `unraid-worker`.

Use `make help` for the short operator targets. `make lab` runs the whole
Omni-only cluster path: provider, MachineClasses, and cluster template sync.

Important boundary: cluster provisioning tasks use Omni (`omnictl`, machine
classes, cluster templates, and the Omni infrastructure provider). They must not
SSH to Unraid, call `virsh`, run Terraform, or create VMs directly. The provider
may connect to libvirt because that is Omni's infrastructure-provider mechanism.

## IaC Flow (Preferred)

This flow bootstraps the Omni control-plane VM itself. It is not the Talos cluster
provisioning path.

```bash
cp templates/omni.env.example .env
# add OMNI_SSH_PUBLIC_KEY_PATH (+ optional OMNI_TAILSCALE_AUTHKEY)

mise run infra:prepare-image
mise run infra:check
mise run infra:init
mise run infra:apply
mise run omni:issue-cert   # optional, for OMNI_TLS_PUBLIC_CERT_FILE/KEY_FILE source
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
- For dual-host TLS (`*.ts.net` + public DNS), set `OMNI_TLS_MODE=caddy-sni`,
  `OMNI_TS_DOMAIN`, and `OMNI_PUBLIC_DOMAIN` in `.env`.
  - Omni binds on `127.0.0.1:8443`.
  - Caddy terminates TLS on `:443` with SNI and proxies to Omni.
- `OMNI_LIBVIRT_BRIDGE` defaults to `br0` for direct LAN IPs and can be set to VLAN bridges like `br0.50`.
- With `br0`, your LAN DHCP must lease to VM MACs on that bridge; if not, `ens3` stays without IPv4 and deploy will fail.
- Optional `OMNI_VM_MAC` can pin the NIC MAC to avoid cloud-init netplan MAC drift after domain replacement.
- Terraform reads base image from local operator path (`OMNI_LOCAL_BASE_IMAGE_PATH`), then imports into libvirt pool.
- If using Unraid, VM/libvirt service must be enabled and reachable.
- Full operator details: `docs/sops/`.
- `ctr:omni:deploy-remote` auto-discovers VM IP from libvirt and renders a generated compose env (`generated/compose.env`) with sane defaults.
- In `caddy-sni` mode, `omni:deploy-remote` handles public TLS assets idempotently:
  - copies public cert/key from `OMNI_TLS_PUBLIC_CERT_FILE` / `OMNI_TLS_PUBLIC_KEY_FILE`
  - lets Caddy obtain and renew `*.ts.net` certs natively through host `tailscaled`
- Prereq checklist: `docs/sops/50-prereq-checklist.md`.
