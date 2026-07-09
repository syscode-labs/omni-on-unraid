# Repository Agent Rules

## Talos Cluster Provisioning

- Answer capability questions first: this repo can fully provision Talos machines through Omni only when an Omni infrastructure provider is configured for the target platform. Without a provider, Omni can only provision clusters from already registered machines.
- For Talos cluster work, use only Omni surfaces: `omnictl`, Omni API, cluster templates, machine classes, and Omni infrastructure providers.
- Do not SSH to Unraid, run `virsh`, run Terraform, create disks, create VMs, copy ISOs, or inspect end hardware for Talos cluster provisioning unless the user explicitly asks for low-level hardware work.
- If machines need to be created on Unraid through Omni, use the libvirt infrastructure provider path in this repo. The provider process may talk to libvirt; agents must not manually talk to libvirt for cluster nodes.
- If provider credentials or an `omniconfig` are missing, stop and state the exact missing Omni credential/config. Do not fall back to direct Unraid access.
- Default lab cluster shape is three schedulable control-plane nodes via a dynamic Omni machine class.

## Omni Control Plane Bootstrap

- `infra:*`, `ctr:infra:*`, `omni:deploy-remote`, and `stack:provision` are only for bootstrapping or maintaining the Omni service VM itself.
- Do not use Omni control-plane bootstrap tasks as part of Talos cluster provisioning.
- When the user asks to provision Talos nodes or a Kubernetes cluster, start with `mise run omni:provider:apply`, `mise run omni:provider:status`, `mise run omni:machineclass:apply`, and `mise run omni:cluster:apply`.
- Tooling must be provided by Nix/devbox/mise, not ad hoc curl-install shell scripts. If YAML rendering needs logic, use the Go renderer under `cmd/omni-render` and keep tests under `internal/omnirender`.

## Required Verification

- Before claiming cluster provisioning is possible, verify current Omni docs or the pinned provider docs for the provider flow.
- Before claiming this repo tooling is ready, run `mise tasks ls` and the relevant shell syntax checks for changed scripts.
