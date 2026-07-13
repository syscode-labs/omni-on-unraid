# Repository Agent Rules

## Talos Cluster Provisioning

- Answer capability questions first: this repo can fully provision Talos machines through Omni only when an Omni infrastructure provider is configured for the target platform. Without a provider, Omni can only provision clusters from already registered machines.
- For Talos cluster work, use only Omni surfaces: `omnictl`, Omni API, cluster templates, machine classes, and Omni infrastructure providers.
- Do not SSH to Unraid, run `virsh`, run Terraform, create disks, create VMs, copy ISOs, or inspect end hardware for Talos cluster provisioning unless the user explicitly asks for low-level hardware work.
- If machines need to be created on Unraid through Omni, use the libvirt infrastructure provider path in this repo. The provider process may talk to libvirt; agents must not manually talk to libvirt for cluster nodes.
- If provider credentials or an `omniconfig` are missing, stop and state the exact missing Omni credential/config. Do not fall back to direct Unraid access.
- Default lab cluster shape is three schedulable control-plane nodes via a dynamic Omni machine class.
- For SideroLink, prefer Tailscale addressing: advertise the machine API as `https://<omni-ts-dns>:8090/`. The WireGuard advertised address is `ip:port`, so use `OMNI_TS_IP`/`OMNI_WG_ADDR` with the Omni Tailscale IP. Do not hardcode LAN IPs for Talos join paths.
- Use `NODES_TAILSCALE_AUTHKEY` for Talos node first-boot Tailscale enrollment. Do not reuse `OMNI_TAILSCALE_AUTHKEY` for Talos nodes; that key is only for the Omni service VM bootstrap path.
- Talos node auth must be unattended: the Tailscale auth key must be reusable and pre-tagged for the node source tag used in tailnet policy, currently `tag:talos`.

## Omni Control Plane Bootstrap

- `infra:*`, `ctr:infra:*`, `omni:deploy-remote`, and `stack:provision` are only for bootstrapping or maintaining the Omni service VM itself.
- Do not use Omni control-plane bootstrap tasks as part of Talos cluster provisioning.
- When the user asks to provision Talos nodes or a Kubernetes cluster, start with `mise run omni:provider:apply`, `mise run omni:provider:status`, `mise run omni:machineclass:apply`, and `mise run omni:cluster:apply`.
- Tooling must be provided by Nix/devbox/mise, not ad hoc curl-install shell scripts. If YAML rendering needs logic, use the Go renderer under `cmd/omni-render` and keep tests under `internal/omnirender`.

## Required Verification

- Before claiming cluster provisioning is possible, verify current Omni docs or the pinned provider docs for the provider flow.
- Before claiming this repo tooling is ready, run `mise tasks ls` and the relevant shell syntax checks for changed scripts.

## Tool Approval Policy

- Separate command approvals into read-only and write/state-changing lanes.
- Read-only diagnostics should run without pausing for user confirmation when the harness permits it. If the harness asks for approval on a read-only diagnostic, request a persistent allowlist prefix for that narrow command family so the same prompt does not repeat.
- Read-only examples: `rtk git status`, `rtk git log`, `rtk git diff`, `rtk gh repo view`, `rtk gh run list`, `rtk gh run view`, `rtk gh release view`, `rtk gh pr view`, `rtk gh pr list`, `rtk gh pr checks`, `rtk curl -I`, `rtk nc -vz`, `rtk tailscale status`, `rtk tailscale ping`, `rtk ssh <host> '<read-only status/log/test command>'`, and `rtk env BROWSER=echo mise exec -- omnictl get ...`.
- Write or state-changing commands must still ask first, with a narrow approval scope. Do not ask for broad persistent write allowlists unless the user explicitly requests that exact automation.
- Write/state-changing examples: `git commit`, `git push`, `gh secret set`, `gh repo create`, `gh pr merge`, `docker compose up/down/restart`, `rsync` to remote hosts, editing remote files, `make provider`, `make mc`, `make cluster`, `mise run omni:*:apply`, deleting/recreating clusters, and anything that can change infrastructure.
- Never print secrets in final answers or logs. If a secret must be passed to a CLI, prefer stdin or a secret manager; if the CLI forces argv, state that risk and rotate afterward.

## Scope Discipline

- Do exactly what the user asked. Do not redesign, generalize, automate, or create new workflows when a direct existing command solves the request.
- If the safest path seems different from the user's requested path, stop and ask before steering.
- For infrastructure refreshes, prefer the smallest direct IaC operation. If the user asks to refresh one Terraform/OpenTofu-managed resource, use targeted plan/apply or replacement for that resource only; do not add CI workflows, orchestration, or repo changes unless explicitly asked.
