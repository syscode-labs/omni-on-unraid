#!/usr/bin/env bash
# Bounded, read-only evidence gate for an unattended Unraid Talos rollout.
set -euo pipefail

cluster_name="${CLUSTER_NAME:-unraid-lab}"
talos_version="${TALOS_VERSION:?TALOS_VERSION is required}"
kubernetes_version="${KUBERNETES_VERSION:?KUBERNETES_VERSION is required}"
attempts="${RELEASE_HEALTH_ATTEMPTS:-30}"
interval="${RELEASE_HEALTH_INTERVAL_SECONDS:-10}"

check_once() {
  local nodes_json node_count evidence_dir talosconfig kubeconfig
  evidence_dir="$(mktemp -d)"
  chmod 700 "$evidence_dir"
  trap 'rm -rf "$evidence_dir"' RETURN
  talosconfig="$evidence_dir/talosconfig"
  kubeconfig="$evidence_dir/kubeconfig"
  # Generate fresh, service-account-authenticated access for this exact
  # release; never depend on a runner user's interactive Omni configuration.
  omnictl kubeconfig -c "$cluster_name" --service-account --user unraid-release-health \
    --ttl 15m --force --merge=false "$kubeconfig" >/dev/null
  omnictl talosconfig -c "$cluster_name" --force --merge=false "$talosconfig" >/dev/null
  export KUBECONFIG="$kubeconfig"
  nodes_json="$(kubectl get nodes -o json)"
  node_count="$(jq '[.items[] | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length' <<<"$nodes_json")"
  [ "$node_count" -eq 3 ] || { echo "expected exactly three Ready Kubernetes nodes, got $node_count" >&2; return 1; }

  jq -e --arg version "$kubernetes_version" '
    .items | length == 3 and
    all(.[]; any(.status.conditions[]; .type == "Ready" and .status == "True")) and
    all(.[]; .status.nodeInfo.kubeletVersion == $version)
  ' <<<"$nodes_json" >/dev/null || { echo "Kubernetes nodes are not all Ready at requested Kubernetes version $kubernetes_version" >&2; return 1; }

  # Confirm all expected cluster members are connected in Omni before using
  # their SideroLink addresses for the Talos service/etcd health probe.
  mapfile -t machine_ids < <(omnictl get clustermachine -o json | jq -r --arg c "$cluster_name" 'select(.metadata.labels["omni.sidero.dev/cluster"] == $c) | .metadata.id')
  [ "${#machine_ids[@]}" -eq 3 ] || { echo "expected exactly three Omni cluster machines, got ${#machine_ids[@]}" >&2; return 1; }
  for id in "${machine_ids[@]}"; do
    omnictl get machines -o json | jq -e --arg id "$id" 'select(.metadata.id == $id and .spec.connected == true)' >/dev/null || { echo "Omni machine $id is not connected" >&2; return 1; }
  done

  mapfile -t addresses < <(jq -r '.items[].status.addresses[] | select(.type == "InternalIP") | .address' <<<"$nodes_json")
  talosctl --talosconfig "$talosconfig" --nodes "$(IFS=,; echo "${addresses[*]}")" health
  talosctl --talosconfig "$talosconfig" --nodes "$(IFS=,; echo "${addresses[*]}")" version --short | grep -Fq "$talos_version"
}

for attempt in $(seq 1 "$attempts"); do
  if check_once; then
    echo "release health passed for ${cluster_name}"
    exit 0
  fi
  echo "release health attempt ${attempt}/${attempts} not yet converged" >&2
  sleep "$interval"
done

echo "release health did not converge within $((attempts * interval)) seconds" >&2
exit 1
