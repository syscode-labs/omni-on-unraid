#!/usr/bin/env bash
# Make unraid-lab's Imp placement asymmetric: 6rrw7n is 7 GiB; the other
# control planes stay at the 4 GiB MachineClass default. This deliberately
# opt-in operation fails closed: it never uses interactive Omni credentials or
# direct hypervisor access.
set -euo pipefail

cluster_name="${CLUSTER_NAME:-unraid-lab}"
target_domain="unraid-lab-control-planes-6rrw7n"
target_memory_mib=7168
apply="${APPLY:-0}"
preflight_only="${PREFLIGHT_ONLY:-0}"
remote_ops="${REMOTE_OPS:-/usr/local/bin/coding-agent-remote-operations-supervisor}"
remote_target="${REMOTE_TARGET:-bookofshadows}"
remote_session="${REMOTE_SESSION:-unraid-imp-control-plane-resize}"
peer_domains=(unraid-lab-control-planes-ng8qnl unraid-lab-control-planes-slhjx6)
all_domains=("$target_domain" "${peer_domains[@]}")

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_sa() {
  set +x
  set -a
  # shellcheck disable=SC1090
  source "$HOME/.hermes/omni/omni.env"
  set +a
  : "${OMNI_ENDPOINT:?OMNI_ENDPOINT missing}"
  : "${OMNI_SERVICE_ACCOUNT_KEY:?OMNI_SERVICE_ACCOUNT_KEY missing}"
}
omni() { require_sa; mise x omnictl@1.11.0 -- omnictl "$@"; }
count_lines() { sed '/^$/d' | wc -l | tr -d ' '; }

case "$preflight_only" in 0|1) ;; *) fail 'PREFLIGHT_ONLY must be 0 or 1' ;; esac
if [ "$apply" != 1 ] && [ "$preflight_only" != 1 ]; then
  fail 'refusing live mutation: set PREFLIGHT_ONLY=1 to validate or APPLY=1 to execute'
fi
command -v "$remote_ops" >/dev/null || fail "remote-operations supervisor $remote_ops is required; direct ssh/virsh is prohibited"
command -v kubectl >/dev/null || fail 'kubectl is required'
command -v talosctl >/dev/null || fail 'talosctl is required'
command -v jq >/dev/null || fail 'jq is required'

# Use Omni resources rather than the decorative `omnictl cluster status` view.
# The recovery exception is deliberately narrower than a generic 2/3 status.
machines="$(omni get Machines.omni.sidero.dev -o json)"
declare -A machine_ids=()
for domain in "${all_domains[@]}"; do
  id="$(jq -r --arg request "$domain" 'select(.metadata.labels["omni.sidero.dev/machine-request"] == $request) | .metadata.id' <<<"$machines")"
  [ "$(printf '%s\n' "$id" | count_lines)" = 1 ] || fail "expected exactly one Omni Machine for $domain"
  machine_ids["$domain"]="$(printf '%s\n' "$id" | sed -n '1p')"
done
target_id="${machine_ids[$target_domain]}"
jq -e --arg id "$target_id" 'select(.metadata.id == $id and .spec.connected == true)' <<<"$machines" >/dev/null || fail "target $target_domain is not connected in Omni"

cluster_status="$(omni get ClusterStatuses.omni.sidero.dev "$cluster_name" -o json)"
cluster_healthy=false
jq -e '.spec.ready == true and .spec.kubernetesapiready == true and .spec.controlplaneready == true and .spec.machines.total == 3 and .spec.machines.healthy == 3 and .spec.machines.connected == 3' <<<"$cluster_status" >/dev/null && cluster_healthy=true

machine_statuses="$(omni get ClusterMachineStatuses.omni.sidero.dev -o json)"
# The configured target must be connected and config-current even in the
# exception path. The ClusterMachineStatus resource's ID is the Machine UUID.
jq -s -e --arg id "$target_id" '
  [ .[] | select(.metadata.id == $id) ] | length == 1 and
  .[0].spec.configuptodate == true and (.[0].spec.managementaddress | type == "string" and length > 0)
' <<<"$machine_statuses" >/dev/null || fail "target $target_domain is not config-current in Omni"
peer_a_id="${machine_ids[${peer_domains[0]}]}"
peer_b_id="${machine_ids[${peer_domains[1]}]}"

recovery_2of3=false
if [ "$cluster_healthy" != true ]; then
  jq -e '.spec.ready == false and .spec.kubernetesapiready == true and .spec.machines.total == 3 and .spec.machines.healthy == 2 and .spec.machines.connected == 3' <<<"$cluster_status" >/dev/null || fail 'cluster is neither Ready (3/3) nor the guarded target-only 2/3 recovery state'
  jq -s -e --arg target "$target_id" --arg peer_a "$peer_a_id" --arg peer_b "$peer_b_id" '
    [ .[] | select(.metadata.id == $target or .metadata.id == $peer_a or .metadata.id == $peer_b) ] as $members |
    $members | length == 3 and
    ([ $members[] | select(.metadata.id == $target and .spec.ready == false) ] | length == 1) and
    ([ $members[] | select(.metadata.id == $peer_a and .spec.ready == true) ] | length == 1) and
    ([ $members[] | select(.metadata.id == $peer_b and .spec.ready == true) ] | length == 1)
  ' <<<"$machine_statuses" >/dev/null || fail '2/3 recovery permits only the designated target to be unhealthy; both named peers must be healthy'
  recovery_2of3=true
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
kubeconfig="$workdir/kubeconfig"
talosconfig="$workdir/talosconfig"
omni kubeconfig -c "$cluster_name" --service-account --user unraid-imp-placement --ttl 30m --force --merge=false "$kubeconfig" >/dev/null
omni talosconfig -c "$cluster_name" --force --merge=false "$talosconfig" >/dev/null
export KUBECONFIG="$kubeconfig"

# Require one-to-one Machine UUID -> Kubernetes node system UUID mapping for all
# three named domains. This prevents a stale/replaced node from being drained.
nodes_json="$(kubectl get nodes -o json)"
declare -A node_names=()
for domain in "${all_domains[@]}"; do
  id="${machine_ids[$domain]}"
  node="$(jq -r --arg name "$domain" --arg id "$id" '
    .items[] | select(.metadata.name == $name and ((.status.nodeInfo.systemUUID | ascii_downcase) == ($id | ascii_downcase))) | .metadata.name
  ' <<<"$nodes_json")"
  [ "$(printf '%s\n' "$node" | count_lines)" = 1 ] || fail "expected one exact Machine UUID to Kubernetes node mapping for $domain"
  node_names["$domain"]="$(printf '%s\n' "$node" | sed -n '1p')"
done
target_node="${node_names[$target_domain]}"

# API readiness is a live Kubernetes check, not just Omni's cached status.
kubectl get --raw=/readyz | grep -Fxq 'ok' || fail 'Kubernetes API /readyz did not succeed'

# Query etcd once through the short-lived Omni service-account Talos config.
# talosctl exposes this membership response as a fixed TSV table (not a COSI
# resource), so validate all fields needed for three voting members explicitly.
etcd_members="$(talosctl --talosconfig "$talosconfig" --nodes "$peer_a_id" etcd members)"
printf '%s\n' "$etcd_members" | awk '
  NR == 1 { if (NF != 8 || $1 != "NODE" || $2 != "ID" || $3 != "HOSTNAME" || $8 != "LEARNER") exit 1; next }
  NF != 6 || $2 == "" || $4 == "" || $5 == "" || $6 != "false" { exit 1 }
  seen_id[$2]++
  seen_host[$3]++
  END {
    if (NR != 4 || length(seen_id) != 3 || length(seen_host) != 3) exit 1
    if (!seen_host["unraid-lab-control-planes-6rrw7n"] || !seen_host["unraid-lab-control-planes-ng8qnl"] || !seen_host["unraid-lab-control-planes-slhjx6"]) exit 1
  }
' || fail 'etcd quorum evidence requires the three expected unique non-learner voting members'

# Validate each named libvirt domain through the remote-operations supervisor.
# dominfo supplies the exact UUID plus current and maximum assigned memory.
"$remote_ops" run --target "$remote_target" --session "$remote_session" -- \
  ssh "$remote_target" "bash -s -- '${all_domains[0]}' '${machine_ids[${all_domains[0]}]}' '${all_domains[1]}' '${machine_ids[${all_domains[1]}]}' '${all_domains[2]}' '${machine_ids[${all_domains[2]}]}'" <<'REMOTE'
set -euo pipefail
while [ "$#" -gt 0 ]; do
  domain="$1"; expected_uuid="$2"; shift 2
  info="$(virsh dominfo "$domain")"
  uuid="$(printf '%s\n' "$info" | awk -F: '/^UUID:/ {gsub(/[[:space:]]/, "", $2); print tolower($2)}')"
  [ "$uuid" = "$(printf '%s' "$expected_uuid" | tr '[:upper:]' '[:lower:]')" ] || { echo 'domain UUID does not match Omni Machine UUID' >&2; exit 1; }
  maximum="$(printf '%s\n' "$info" | awk -F: '/^Max memory:/ {gsub(/[^0-9]/, "", $2); print $2}')"
  current="$(printf '%s\n' "$info" | awk -F: '/^Used memory:/ {gsub(/[^0-9]/, "", $2); print $2}')"
  case "$domain" in
    unraid-lab-control-planes-6rrw7n)
      { [ "$maximum" = 4194304 ] && [ "$current" = 4194304 ]; } || { [ "$maximum" = 7340032 ] && [ "$current" = 7340032 ]; } || { echo 'unexpected target current/max memory' >&2; exit 1; }
      ;;
    *)
      [ "$maximum" = 4194304 ] && [ "$current" = 4194304 ] || { echo 'ordinary control-plane memory is not 4096 MiB' >&2; exit 1; }
      ;;
  esac
done
REMOTE

if [ "$preflight_only" = 1 ]; then
  printf 'preflight passed: %s is the only permitted unhealthy member and 7+4+4 resize prerequisites are satisfied\n' "$target_domain"
  exit 0
fi

# Omni's ConfigPatch is machine-ID-scoped. It persists the target label across
# node reboots/replacement of kubelet state; no global Imp label patch is used.
cat >"$workdir/target-config-patch.yaml" <<EOF
metadata:
  namespace: default
  type: ConfigPatches.omni.sidero.dev
  id: imp-placement-${target_id}
  labels:
    omni.sidero.dev/machine: ${target_id}
spec:
  data: |
    apiVersion: v1alpha1
    kind: KubeNodeConfig
    labels:
      imp/enabled: "true"
    taints:
      imp.dev/runner:
        value: "true"
        effect: NoSchedule
EOF
omni apply -f "$workdir/target-config-patch.yaml"

for domain in "${peer_domains[@]}"; do
  node="${node_names[$domain]}"
  kubectl label node "$node" imp/enabled- --ignore-not-found
  kubectl taint node "$node" imp.dev/runner- --ignore-not-found
done
kubectl label node "$target_node" imp/enabled=true --overwrite
kubectl taint node "$target_node" imp.dev/runner=true:NoSchedule --overwrite
kubectl cordon "$target_node"
kubectl drain "$target_node" --ignore-daemonsets --delete-emptydir-data --timeout=10m

# Re-check structured XML immediately before mutating through the supervisor;
# this closes the gap between read-only preflight and shutdown.
"$remote_ops" run --target "$remote_target" --session "$remote_session" -- \
  ssh "$remote_target" "bash -s -- '$target_domain' '$target_memory_mib'" <<'REMOTE'
set -euo pipefail
domain="$1"; target="$2"
[ "$domain" = unraid-lab-control-planes-6rrw7n ] || { echo 'unexpected domain' >&2; exit 1; }
[ "$target" = 7168 ] || { echo 'unexpected target memory' >&2; exit 1; }
info="$(virsh dominfo "$domain")"
maximum="$(printf '%s\n' "$info" | awk -F: '/^Max memory:/ {gsub(/[^0-9]/, "", $2); print $2}')"
current="$(printf '%s\n' "$info" | awk -F: '/^Used memory:/ {gsub(/[^0-9]/, "", $2); print $2}')"
{ [ "$maximum" = 4194304 ] && [ "$current" = 4194304 ]; } || { [ "$maximum" = 7340032 ] && [ "$current" = 7340032 ]; } || { echo 'unexpected target current/max memory' >&2; exit 1; }
state="$(virsh domstate "$domain" | tr -d '\r' | xargs)"
case "$state" in running) virsh shutdown "$domain" ;; 'shut off') : ;; *) echo "unexpected domain state: $state" >&2; exit 1 ;; esac
for _ in $(seq 1 60); do [ "$(virsh domstate "$domain" | tr -d '\r' | xargs)" = 'shut off' ] && break; sleep 5; done
[ "$(virsh domstate "$domain" | tr -d '\r' | xargs)" = 'shut off' ] || { echo 'domain did not shut down' >&2; exit 1; }
virsh setmaxmem "$domain" "$target" --config --size MiB
virsh setmem "$domain" "$target" --config --size MiB
virsh start "$domain"
[ "$(virsh domstate "$domain" | tr -d '\r' | xargs)" = running ] || { echo 'domain did not start' >&2; exit 1; }
REMOTE

kubectl wait --for=condition=Ready "node/$target_node" --timeout=15m
kubectl get node "$target_node" -o json | jq -e '.metadata.labels["imp/enabled"] == "true" and any(.spec.taints[]?; .key == "imp.dev/runner" and .value == "true" and .effect == "NoSchedule")' >/dev/null || fail 'target Imp placement did not converge'
omni cluster status "$cluster_name" --wait=0 | tee /dev/stderr | grep -Fq 'RUNNING Ready (3/3)' || fail 'cluster did not return to Ready (3/3)'
kubectl uncordon "$target_node"
[ "$recovery_2of3" = true ] && printf 'guarded target-only 2/3 recovery preflight accepted\n'
printf 'completed %s: target %s (%s) is 7168 MiB; ordinary nodes remain at the 4096 MiB MachineClass default\n' "$cluster_name" "$target_node" "$target_domain"
