#!/usr/bin/env bash
set -euo pipefail

# Reconcile stale/disconnected cluster members before omni:cluster:apply sync.
#
# Guards against the "maintenance deadlock" seen on oci-lab (2026-08-06/07):
# a member Omni has begun tearing down but can no longer reach stays in the
# cluster resource set forever, blocking config generation for every other
# machine in the set. Machine sets then stall with a confighash equal to the
# SHA-256 of the empty string (e3b0c442...) and the cluster never becomes
# ready. The only way to evict such a member is to delete its SideroLink,
# which lets the machine teardown chain complete as if the machine is gone
# (omnictl delete link; see siderolabs/omni#2465).
#
# This script:
#   1. Lists members of CLUSTER_NAME from ClusterMachines.omni.sidero.dev.
#   2. Correlates each member with Machines.omni.sidero.dev phase/connected.
# 3. Purges members in tearingDown/Destroyed phase that are disconnected by
#      deleting their SideroLink (unblocks the teardown chain — see
#      siderolabs/omni#2465; `cluster machine delete --force` only helps
#      reachable unjoined control planes, and cluster delete
#      --destroy-disconnected-machines nukes the whole cluster).
#   4. Fails loudly if any machine set of the cluster still carries the
#      empty-string confighash after reconcile, so the caller never syncs a
#      template over unresolved config.
#
# Connected members are never purged (a disconnected-but-running machine is
# only a reboot). Phase "running" is always preserved.
#
# Usage:
#   reconcile-cluster-machines.sh [--dry-run] CLUSTER_NAME
# Env:
#   OMNICONFIG   path to omni config (omnictl requirement)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

EMPTY_SHA="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

dry_run=false
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=true
  shift
fi

cluster_name="${1:-${CLUSTER_NAME:-}}"
if [ -z "$cluster_name" ]; then
  echo "usage: $0 [--dry-run] CLUSTER_NAME" >&2
  exit 1
fi

command -v omnictl >/dev/null 2>&1 || {
  echo "reconcile-cluster-machines: omnictl not found on PATH" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "reconcile-cluster-machines: jq not found on PATH" >&2
  exit 1
}

info()  { printf '[reconcile] %s\n' "$*"; }
warn()  { printf '[reconcile] WARNING: %s\n' "$*" >&2; }
fail()  { printf '[reconcile] ERROR: %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
# Machine membership + liveness maps.
# --------------------------------------------------------------------------
# id -> machine-set for the target cluster (from ClusterMachines labels).
declare -A set_members=()
while IFS=$'\t' read -r id set_name; do
  [ -n "$id" ] && set_members["$id"]="$set_name"
done < <(omnictl get clustermachine -o json 2>/dev/null \
  | jq -r --arg c "$cluster_name" \
      'select(.metadata.labels["omni.sidero.dev/cluster"] == $c)
       | [.metadata.id, (.metadata.labels["omni.sidero.dev/machine-set"] // "?")] | @tsv')

if [ "${#set_members[@]}" -eq 0 ]; then
  info "no cluster members found for cluster '${cluster_name}'"
  exit 0
fi

# id -> phase / connected
declare -A machine_phase machine_connected
while IFS=$'\t' read -r id phase connected; do
  machine_phase["$id"]="$phase"
  machine_connected["$id"]="$connected"
done < <(omnictl get machines -o json 2>/dev/null \
  | jq -r '[.metadata.id, .metadata.phase, (.spec.connected|tostring)] | @tsv')

# --------------------------------------------------------------------------
# 3. Purge stuck teardowns: phase tearingDown/Destroyed AND disconnected.
# --------------------------------------------------------------------------
purged=()
for id in "${!set_members[@]}"; do
  phase="${machine_phase[$id]:-unknown}"
  connected="${machine_connected[$id]:-unknown}"
  if { [ "$phase" = "tearingDown" ] || [ "$phase" = "Destroyed" ]; } && [ "$connected" != "true" ]; then
    info "stale member: ${id} (${set_members[$id]}) ${phase}, connected=${connected}"
    purged+=("$id")
  fi
done

if [ "${#purged[@]}" -gt 0 ]; then
  if [ "$dry_run" = true ]; then
    for id in "${purged[@]}"; do
      info "would purge (dry-run): ${id}"
    done
  else
    for id in "${purged[@]}"; do
      info "removing stale member link: ${id}"
      # Deleting the SideroLink is the supported escape hatch for a member
      # Omni is tearing down but can never reach again. cluster machine
      # delete --force only covers reachable etcd-unjoined control planes;
      # this path covers the disconnected case (siderolabs/omni#2465).
      omnictl delete link "$id"
    done
  fi
fi

# --------------------------------------------------------------------------
# 4. Config-bundle liveness: any set still hashing the empty string means no
#    config reached its machines -> fail loudly rather than sync a template.
# --------------------------------------------------------------------------
bad_sets=()
while IFS=$'\t' read -r set_name confighash connected requested; do
  if [ "$confighash" = "$EMPTY_SHA" ] && [ "$requested" -gt 0 ] && [ "$connected" -gt 0 ]; then
    bad_sets+=("$set_name")
  fi
done < <(omnictl get machinesetstatus -o json 2>/dev/null \
  | jq -r --arg c "$cluster_name" \
      'select(.metadata.labels["omni.sidero.dev/cluster"] == $c)
       | [.metadata.id, .spec.confighash, (.spec.machines.connected|tostring), (.spec.machines.requested|tostring)] | @tsv')

if [ "${#bad_sets[@]}" -gt 0 ]; then
  if [ "$dry_run" = true ]; then
    warn "machine sets with empty config hash (maintenance deadlock signature): ${bad_sets[*]}"
    exit 0
  fi
  fail "machine sets still hash empty config after reconcile: ${bad_sets[*]}; no config was generated for these sets, refusing to sync over them."
fi

info "reconcile ok for cluster '${cluster_name}'"
exit 0