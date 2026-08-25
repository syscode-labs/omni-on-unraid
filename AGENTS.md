# Repository Agent Rules

## Talos Cluster Provisioning

- Answer capability questions first: this repo can fully provision Talos machines through Omni only when an Omni infrastructure provider is configured for the target platform. Without a provider, Omni can only provision clusters from already registered machines.
- For Talos cluster work, use only Omni surfaces: `omnictl`, Omni API, cluster templates, machine classes, and Omni infrastructure providers.
- Use the remote-operations supervisor for all SSH and libvirt access to Unraid. Never bypass it with direct SSH, `virsh`, or another unmanaged remote/hardware command.
- If the supervisor denies an action or cannot perform it, do not fall back to direct access. Seek explicit authorization in the current message before proposing or performing a bypass, naming the target and action. A reference to prior work, a request to “continue,” or a request to “check” is never authorization to bypass the supervisor.
- If machines need to be created on Unraid through Omni, use the libvirt infrastructure provider path in this repo. The provider process may talk to libvirt; agents must not manually talk to libvirt for cluster nodes.
- If provider credentials or an `omniconfig` are missing, stop and state the exact missing Omni credential/config. Do not fall back to direct Unraid access.
- Default lab cluster shape is three schedulable control-plane nodes via a dynamic Omni machine class.
- For SideroLink, Omni advertises its endpoint over the tailnet: machine API `https://<omni-ts-dns>:8090/`, WireGuard `<omni-ts-ip>:50180`. Do not hardcode LAN IPs for Talos join paths — the join must stay tailnet-only.
- Nodes do NOT run Tailscale (early tailscale is removed — it hangs on `cri` in maintenance mode). They reach the tailnet-only Omni by routing: the libvirt host advertises the VM subnet into the tailnet, an ACL grant permits `<vm-subnet> -> tag:omni:8090,50180`, and a libvirt-masquerade exemption preserves the VM source IP. See `docs/sops/60-tailscale-omni-network.md` and the plans-repo findings doc `2026-07-16-libvirt-unraid-lab-tailnet-join.md`.

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
- Exception: SSH to Unraid and all libvirt/hardware diagnostics must use the remote-operations supervisor. Explicit authorization is required only to bypass that supervisor. This exception takes priority over the general read-only rule.
- Read-only examples: `rtk git status`, `rtk git log`, `rtk git diff`, `rtk gh repo view`, `rtk gh run list`, `rtk gh run view`, `rtk gh release view`, `rtk gh pr view`, `rtk gh pr list`, `rtk gh pr checks`, `rtk curl -I`, `rtk nc -vz`, `rtk tailscale status`, `rtk tailscale ping`, `rtk ssh <host> '<read-only status/log/test command>'`, and `rtk env BROWSER=echo mise exec -- omnictl get ...`.
- Write or state-changing commands must still ask first, with a narrow approval scope. Do not ask for broad persistent write allowlists unless the user explicitly requests that exact automation.
- Write/state-changing examples: `git commit`, `git push`, `gh secret set`, `gh repo create`, `gh pr merge`, `docker compose up/down/restart`, `rsync` to remote hosts, editing remote files, `make provider`, `make mc`, `make cluster`, `mise run omni:*:apply`, deleting/recreating clusters, and anything that can change infrastructure.
- For an explicitly authorized Omni force destroy, submit the force request and return immediately. Do not wait for finalizer teardown; check its status separately.
- Never print secrets in final answers or logs. If a secret must be passed to a CLI, prefer stdin or a secret manager; if the CLI forces argv, state that risk and rotate afterward.

## Scope Discipline

- Do exactly what the user asked. Do not redesign, generalize, automate, or create new workflows when a direct existing command solves the request.
- If the safest path seems different from the user's requested path, stop and ask before steering.
- For infrastructure refreshes, prefer the smallest direct IaC operation. If the user asks to refresh one Terraform/OpenTofu-managed resource, use targeted plan/apply or replacement for that resource only; do not add CI workflows, orchestration, or repo changes unless explicitly asked.
