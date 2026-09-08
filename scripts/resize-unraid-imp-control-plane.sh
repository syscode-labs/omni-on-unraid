#!/usr/bin/env bash
# Make unraid-lab's Imp placement asymmetric: 6rrw7n is 7 GiB; the other
# control planes stay at the 4 GiB MachineClass default.  This script is
# deliberately opt-in because it cordons, drains, powers off, and resizes one
# control-plane VM.  It never falls back to interactive Omni credentials or
# direct hypervisor access.
set -euo pipefail

cluster_name="${CLUSTER_NAME:-unraid-lab}"
target_domain="unraid-lab-control-planes-6rrw7n"
target_memory_mib=7168
apply="${APPLY:-0}"
remote_ops="${REMOTE_OPS:-rtk}"

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

[ "$apply" = 1 ] || fail 'refusing live mutation: re-run with APPLY=1 after the preflight is green'
command -v "$remote_ops" >/dev/null || fail "remote-operations supervisor $remote_ops is required; direct ssh/virsh is prohibited"
command -v kubectl >/dev/null || fail 'kubectl is required'
command -v jq >/dev/null || fail 'jq is required'

# Parse Omni's JSON stream and fail closed unless the exact three live provider
# requests and the designated target identity are present and connected.
machines="$(omni get machines -o json)"
target_id="$(jq -r --arg request "$target_domain" 'select(.metadata.labels["omni.sidero.dev/machine-request"] == $request) | .metadata.id' <<<"$machines")"
[ "$(printf '%s\n' "$target_id" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || fail "expected exactly one Omni Machine for $target_domain"
target_id="$(printf '%s\n' "$target_id" | sed -n '1p')"
for suffix in 6rrw7n ng8qnl slhjx6; do
  request="unraid-lab-control-planes-$suffix"
  count="$(jq -r --arg request "$request" 'select(.metadata.labels["omni.sidero.dev/machine-request"] == $request) | .metadata.id' <<<"$machines" | sed '/^$/d' | wc -l | tr -d ' ')"
  [ "$count" = 1 ] || fail "expected exactly one live machine for $request, got $count"
done
jq -e --arg id "$target_id" 'select(.metadata.id == $id and .spec.connected == true)' <<<"$machines" >/dev/null || fail "target $target_domain is not connected in Omni"

# A resize is safe only from an already healthy three-member control plane.
omni cluster status "$cluster_name" | tee /dev/stderr | grep -Fq 'RUNNING Ready (3/3)' || fail 'cluster is not Ready (3/3); do not drain or resize'

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
kubeconfig="$workdir/kubeconfig"
omni kubeconfig -c "$cluster_name" --service-account --user unraid-imp-placement --ttl 30m --force --merge=false "$kubeconfig" >/dev/null
export KUBECONFIG="$kubeconfig"

# Require a unique Kubernetes node matching each Omni machine request.  The
# node-name label is the durable domain mapping; never select by IP/order.
target_node="$(kubectl get nodes -o json | jq -r --arg request "$target_domain" '.items[] | select(.metadata.labels["omni.sidero.dev/machine-request"] == $request) | .metadata.name')"
[ "$(printf '%s\n' "$target_node" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || fail "expected exactly one Kubernetes node mapped to $target_domain"
target_node="$(printf '%s\n' "$target_node" | sed -n '1p')"

# Omni's ConfigPatch is machine-ID-scoped.  It persists the target label across
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

# Kubernetes labels/taints are reconciled idempotently now; the ConfigPatch
# above makes the label durable at the Talos/Omni layer.  Clear the old global
# label from the two ordinary control planes.
for suffix in ng8qnl slhjx6; do
  request="unraid-lab-control-planes-$suffix"
  node="$(kubectl get nodes -o json | jq -r --arg request "$request" '.items[] | select(.metadata.labels["omni.sidero.dev/machine-request"] == $request) | .metadata.name')"
  [ "$(printf '%s\n' "$node" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || fail "expected exactly one Kubernetes node mapped to $request"
  kubectl label node "$node" imp/enabled- --ignore-not-found
  kubectl taint node "$node" imp.dev/runner- --ignore-not-found
 done
kubectl label node "$target_node" imp/enabled=true --overwrite
kubectl taint node "$target_node" imp.dev/runner=true:NoSchedule --overwrite

kubectl cordon "$target_node"
kubectl drain "$target_node" --ignore-daemonsets --delete-emptydir-data --timeout=10m

# All hypervisor access is through the remote-operations supervisor.  The
# remote program validates exact domain identity and memory before changing it;
# it cannot select a VM by prefix or proceed after an unexpected state.
"$remote_ops" ssh frigate-unraid "bash -s -- '$target_domain' '$target_memory_mib'" <<'REMOTE'
set -euo pipefail
domain="$1"; target="$2"
[ "$domain" = unraid-lab-control-planes-6rrw7n ] || { echo 'unexpected domain' >&2; exit 1; }
[ "$target" = 7168 ] || { echo 'unexpected target memory' >&2; exit 1; }
virsh dominfo "$domain" >/dev/null
state="$(virsh domstate "$domain" | tr -d '\r' | xargs)"
case "$state" in
  running) virsh shutdown "$domain" ;;
  'shut off') : ;;
  *) echo "unexpected domain state: $state" >&2; exit 1 ;;
esac
for _ in $(seq 1 60); do
  [ "$(virsh domstate "$domain" | tr -d '\r' | xargs)" = 'shut off' ] && break
  sleep 5
done
[ "$(virsh domstate "$domain" | tr -d '\r' | xargs)" = 'shut off' ] || { echo 'domain did not shut down' >&2; exit 1; }
current="$(virsh dominfo "$domain" | awk -F: '/^Max memory:/ {gsub(/[^0-9]/,"",$2); print $2}')"
[ "$current" = 4194304 ] || [ "$current" = 7340032 ] || { echo "unexpected max memory KiB: $current" >&2; exit 1; }
virsh setmaxmem "$domain" "$target" --config --size MiB
virsh setmem "$domain" "$target" --config --size MiB
virsh start "$domain"
[ "$(virsh domstate "$domain" | tr -d '\r' | xargs)" = running ] || { echo 'domain did not start' >&2; exit 1; }
REMOTE

kubectl wait --for=condition=Ready "node/$target_node" --timeout=15m
kubectl get node "$target_node" -o json | jq -e '.metadata.labels["imp/enabled"] == "true" and any(.spec.taints[]?; .key == "imp.dev/runner" and .value == "true" and .effect == "NoSchedule")' >/dev/null || fail 'target Imp placement did not converge'
omni cluster status "$cluster_name" | tee /dev/stderr | grep -Fq 'RUNNING Ready (3/3)' || fail 'cluster did not return to Ready (3/3)'
kubectl uncordon "$target_node"
printf 'completed %s: target %s (%s) is 7168 MiB; ordinary nodes remain at the 4096 MiB MachineClass default\n' "$cluster_name" "$target_node" "$target_domain"
