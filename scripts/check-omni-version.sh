#!/usr/bin/env bash
set -euo pipefail

# Fails loudly if the omnictl on PATH doesn't match the Omni server version.
#
# omnictl itself only prints a non-fatal warning on mismatch and keeps going —
# on 2026-07-28 that silently half-broke cluster provisioning against
# unraid-lab: ClusterBootstrapStatus flipped to bootstrapped=true without
# etcd ever initializing on any node, no error surfaced anywhere. `mise`
# pins omnictl (see [tools] in mise.toml) to track the deployed server, but
# a stray global omnictl earlier in PATH silently overrides that pin — this
# check catches that regardless of how the mismatch happens.

output="$(omnictl get clusters 2>&1 >/dev/null || true)"

if echo "$output" | grep -q 'differs from the backend version'; then
  echo "FATAL: omnictl/Omni server version mismatch — refusing to proceed." >&2
  echo "$output" >&2
  echo "Fix: run 'mise install' to get the pinned omnictl, or check PATH for a stray global install ahead of mise's shim." >&2
  exit 1
fi
