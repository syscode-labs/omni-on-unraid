#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
production_script="$root/scripts/resize-unraid-imp-control-plane.sh"
bash -n "$production_script"
shellcheck -e SC1091 "$production_script"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.hermes/omni"
printf 'OMNI_ENDPOINT=https://example.invalid\nOMNI_SERVICE_ACCOUNT_KEY=test-only\n' >"$tmp/home/.hermes/omni/omni.env"
script="$tmp/resize-unraid-imp-control-plane.sh"
python3 - "$production_script" "$script" "$tmp/bin/rtk" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
old = 'remote_ops="rtk"'
if source.count(old) != 1:
    raise SystemExit("production must use the exact fixed rtk remote contract")
Path(sys.argv[2]).write_text(source.replace(old, f'remote_ops="{sys.argv[3]}"'))
PY
chmod +x "$script"

cat >"$tmp/bin/mise" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
shift 4 # mise x omnictl@... -- omnictl
case "$1 ${2:-}" in
  'get Machines.omni.sidero.dev')
    cat <<JSON
{"metadata":{"id":"ee285972-e7d5-433e-a67c-efb924707a8c","labels":{"omni.sidero.dev/machine-request":"unraid-lab-control-planes-6rrw7n"}},"spec":{"connected":$( [ "${SCENARIO:-healthy}" = disconnected ] && echo false || echo true )}}
{"metadata":{"id":"1ebbe497-22fc-42a9-8ca9-eaa1f339ea83","labels":{"omni.sidero.dev/machine-request":"unraid-lab-control-planes-ng8qnl"}},"spec":{"connected":$( [ "${SCENARIO:-healthy}" = peer-disconnected ] && echo false || echo true )}}
{"metadata":{"id":"5db9ed95-99dd-4d05-ab36-57707f4ec92b","labels":{"omni.sidero.dev/machine-request":"unraid-lab-control-planes-slhjx6"}},"spec":{"connected":true}}
JSON
    ;;
  'get ClusterStatuses.omni.sidero.dev')
    case "${SCENARIO:-healthy}" in
      healthy) echo '{"spec":{"ready":true,"kubernetesapiready":true,"controlplaneready":true,"machines":{"total":3,"healthy":3,"connected":3}}}' ;;
      *) echo '{"spec":{"ready":false,"kubernetesapiready":true,"controlplaneready":false,"machines":{"total":3,"healthy":2,"connected":3}}}' ;;
    esac
    ;;
  'get ClusterMachineStatuses.omni.sidero.dev')
    target_ready=false; [ "${SCENARIO:-healthy}" = healthy ] && target_ready=true
    peer_a=true; peer_b=true; [ "${SCENARIO:-healthy}" = other-unhealthy ] && peer_a=false
    config_current=true; [ "${SCENARIO:-healthy}" = config-stale ] && config_current=false
    cat <<JSON
{"metadata":{"id":"ee285972-e7d5-433e-a67c-efb924707a8c"},"spec":{"ready":$target_ready,"configuptodate":$config_current,"managementaddress":"10.0.0.1"}}
{"metadata":{"id":"1ebbe497-22fc-42a9-8ca9-eaa1f339ea83"},"spec":{"ready":$peer_a,"configuptodate":true,"managementaddress":"10.0.0.2"}}
{"metadata":{"id":"5db9ed95-99dd-4d05-ab36-57707f4ec92b"},"spec":{"ready":$peer_b,"configuptodate":true,"managementaddress":"10.0.0.3"}}
JSON
    ;;
  kubeconfig\ *|talosconfig\ *) : >"${@: -1}" ;;
  apply\ *)
    [ "$#" = 3 ] && [ "$2" = -f ] || { echo "unexpected config apply invocation: $*" >&2; exit 2; }
    python3 - "$3" <<'PY'
from pathlib import Path
import sys

patch = Path(sys.argv[1]).read_text()
expected = '''metadata:
  namespace: default
  type: ConfigPatches.omni.sidero.dev
  id: imp-placement-ee285972-e7d5-433e-a67c-efb924707a8c
  labels:
    omni.sidero.dev/machine: ee285972-e7d5-433e-a67c-efb924707a8c
spec:
  data: |
    apiVersion: v1alpha1
    kind: KubeNodeConfig
    labels:
      imp/enabled: "true"
    taints:
      imp.dev/runner: "true:NoSchedule"
'''
if patch != expected:
    raise SystemExit("generated ConfigPatch must be machine-scoped and render imp.dev/runner as the exact scalar true:NoSchedule")
if 'value:' in patch or 'effect:' in patch:
    raise SystemExit("generated ConfigPatch must not use nested taint value/effect fields")
PY
    printf 'omni:%s\n' "$*" >>"$CALL_LOG"
    [ "${SCENARIO:-healthy}" != config-apply-failed ]
    ;;
  'cluster status')
    [ "$*" = 'cluster status unraid-lab --wait=15m' ] || { echo "unexpected cluster status invocation: $*" >&2; exit 2; }
    [ "${SCENARIO:-healthy}" = final-status-failed ] && echo 'RUNNING Not Ready (2/3)' || echo 'RUNNING Ready (3/3)'
    ;;
  *) echo "unexpected omnictl invocation: $*" >&2; exit 2 ;;
esac
MOCK
cat >"$tmp/bin/kubectl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'kubectl:%s\n' "$*" >>"$CALL_LOG"
if [ "$1 $2" = 'get nodes' ]; then
  target='ee285972-e7d5-433e-a67c-efb924707a8c'; [ "${SCENARIO:-healthy}" = identity-mismatch ] && target='00000000-0000-0000-0000-000000000000'
  unschedulable=false; [ "${SCENARIO:-healthy}" = initially-cordoned ] && unschedulable=true
  cat <<JSON
{"items":[{"metadata":{"name":"unraid-lab-control-planes-6rrw7n"},"spec":{"unschedulable":$unschedulable},"status":{"nodeInfo":{"systemUUID":"$target"}}},{"metadata":{"name":"unraid-lab-control-planes-ng8qnl"},"status":{"nodeInfo":{"systemUUID":"1ebbe497-22fc-42a9-8ca9-eaa1f339ea83"}}},{"metadata":{"name":"unraid-lab-control-planes-slhjx6"},"status":{"nodeInfo":{"systemUUID":"5db9ed95-99dd-4d05-ab36-57707f4ec92b"}}}]}
JSON
elif [ "$1" = get ] && [ "${2:-}" = --raw=/readyz ]; then
  [ "${SCENARIO:-healthy}" = api-failed ] && exit 1; echo ok
elif [ "$1 ${2:-}" = 'get node' ]; then
  if [ "${SCENARIO:-healthy}" = placement-failed ]; then
    echo '{"metadata":{"labels":{}},"spec":{"taints":[]}}'
  else
    echo '{"metadata":{"labels":{"imp/enabled":"true"}},"spec":{"taints":[{"key":"imp.dev/runner","value":"true","effect":"NoSchedule"}]}}'
  fi
elif [ "$1" = wait ]; then
  count_file="${CALL_LOG}.wait-count"
  count=0; [ -f "$count_file" ] && count="$(cat "$count_file")"
  count=$((count + 1)); printf '%s' "$count" >"$count_file"
  [ "${SCENARIO:-healthy}" = remote-failed ] && exit 1
  [ "${SCENARIO:-healthy}" = post-wait-failed ] && [ "$count" -eq 1 ] && exit 1
  exit 0
elif [ "$1" = drain ]; then
  [ "${SCENARIO:-healthy}" = drain-failed ] && exit 1
  exit 0
elif [ "$1" = uncordon ]; then
  [ "${SCENARIO:-healthy}" = uncordon-failed ] && exit 1
  exit 0
elif [ "$1" = label ] || [ "$1" = taint ] || [ "$1" = cordon ]; then
  exit 0
else
  echo "unexpected kubectl invocation: $*" >&2
  exit 2
fi
MOCK
cat >"$tmp/bin/talosctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
cat <<EOF
NODE ID HOSTNAME PEER URLS CLIENT URLS LEARNER
10.0.0.1 a unraid-lab-control-planes-6rrw7n https://one https://one false
10.0.0.1 b unraid-lab-control-planes-ng8qnl https://two https://two false
10.0.0.1 c $( [ "${SCENARIO:-healthy}" = etcd-wrong-member ] && echo stale-member || echo unraid-lab-control-planes-slhjx6 ) https://three https://three $( [ "${SCENARIO:-healthy}" = etcd-learner ] && echo true || echo false )
EOF
MOCK
cat >"$tmp/bin/rtk" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" = 3 ] && [ "$1" = ssh ] && [ "$2" = frigate-unraid ] || exit 2
case "$3" in 'bash -s -- '*) ;; *) exit 2 ;; esac
body="$(cat)"
if printf '%s' "$body" | grep -Fq 'virsh setmaxmem'; then
  printf 'rtk:ssh frigate-unraid:mutate\n' >>"$CALL_LOG"
  export VIRSH_MUTATION=1
else
  printf 'rtk:ssh frigate-unraid:preflight\n' >>"$CALL_LOG"
  unset VIRSH_MUTATION
  [ "${SCENARIO:-healthy}" = unexpected-memory ] && exit 1
fi
eval "set -- ${3#bash -s -- }"
printf '%s' "$body" | /bin/bash -s -- "$@"
MOCK
cat >"$tmp/bin/virsh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'virsh:%s\n' "$*" >>"$CALL_LOG"
state_file="${CALL_LOG}.vm-state"
state=running; [ -f "$state_file" ] && state="$(cat "$state_file")"
case "$1" in
  dominfo)
    case "$2" in
      unraid-lab-control-planes-6rrw7n)
        uuid=ee285972-e7d5-433e-a67c-efb924707a8c
        [ "${SCENARIO:-healthy}" = mutation-uuid-mismatch ] && [ "${VIRSH_MUTATION:-0}" = 1 ] && uuid=00000000-0000-0000-0000-000000000000
        ;;
      unraid-lab-control-planes-ng8qnl) uuid=1ebbe497-22fc-42a9-8ca9-eaa1f339ea83 ;;
      unraid-lab-control-planes-slhjx6) uuid=5db9ed95-99dd-4d05-ab36-57707f4ec92b ;;
      *) exit 2 ;;
    esac
    cat <<EOF
Id: 1
Name: $2
UUID: $uuid
OS Type: hvm
State: $state
Max memory: 4194304 KiB
Used memory: 4194304 KiB
EOF
    ;;
  domstate) printf '%s\n' "$state" ;;
  shutdown)
    [ "${SCENARIO:-healthy}" = remote-shutdown-failed ] && exit 1
    printf 'shut off' >"$state_file"
    ;;
  setmaxmem) [ "${SCENARIO:-healthy}" != remote-setmaxmem-failed ] ;;
  setmem) [ "${SCENARIO:-healthy}" != remote-setmem-failed ] ;;
  start)
    starts_file="${CALL_LOG}.start-count"
    starts=0; [ -f "$starts_file" ] && starts="$(cat "$starts_file")"
    starts=$((starts + 1)); printf '%s' "$starts" >"$starts_file"
    [ "${SCENARIO:-healthy}" = remote-start-failed ] && [ "$starts" -eq 1 ] && exit 1
    printf running >"$state_file"
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$tmp/bin"/*

run_case() {
  local scenario="$1" want="$2" expected="$3" preflight="${4:-0}" output status
  export CALL_LOG="$tmp/calls-$scenario-$preflight"
  rm -f "$CALL_LOG" "$CALL_LOG.wait-count"
  set +e
  output="$(PATH="$tmp/bin:$PATH" HOME="$tmp/home" APPLY=$((1 - preflight)) PREFLIGHT_ONLY="$preflight" SCENARIO="$scenario" CALL_LOG="$CALL_LOG" "$script" 2>&1)"
  status=$?
  set -e
  if [ "$expected" = pass ]; then
    [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
  else
    [ "$status" -ne 0 ] || { printf '%s unexpectedly passed\n' "$scenario" >&2; return 1; }
    printf '%s\n' "$output" | grep -Fq "$want" || { printf '%s\n' "$output" >&2; return 1; }
  fi
}

assert_log() { grep -Fq "$2" "$1" || { printf 'missing call log entry: %s\n' "$2" >&2; return 1; }; }
assert_no_log() { ! grep -Eq "$2" "$1" || { printf 'unexpected call log match: %s\n' "$2" >&2; return 1; }; }
assert_in_order() {
  local log="$1" entry line last=0
  shift
  for entry in "$@"; do
    line="$(grep -n -F "$entry" "$log" | cut -d: -f1 | awk -v last="$last" '$1 > last { print; exit }')"
    [ -n "$line" ] || { printf 'missing or out-of-order call log entry: %s\n' "$entry" >&2; return 1; }
    last="$line"
  done
}

# Both accepted paths.
run_case healthy '' pass
assert_in_order "$CALL_LOG" \
  'rtk:ssh frigate-unraid:mutate' \
  'virsh:shutdown unraid-lab-control-planes-6rrw7n' \
  'virsh:setmaxmem unraid-lab-control-planes-6rrw7n 7168 --config --size MiB' \
  'virsh:setmem unraid-lab-control-planes-6rrw7n 7168 --config --size MiB' \
  'virsh:start unraid-lab-control-planes-6rrw7n' \
  'kubectl:wait --for=condition=Ready node/unraid-lab-control-planes-6rrw7n --timeout=15m' \
  'kubectl:uncordon unraid-lab-control-planes-6rrw7n'
run_case recovery-2of3 '' pass
run_case recovery-2of3 '' pass 1
assert_no_log "$CALL_LOG" '^(omni:|rtk:ssh frigate-unraid:mutate|kubectl:(label|taint|cordon|drain|uncordon))'
# Critical rejection gates.
run_case other-unhealthy 'both named peers must be healthy' fail
run_case api-failed 'API /readyz did not succeed' fail
run_case etcd-learner 'three expected unique non-learner voting members' fail
run_case etcd-wrong-member 'three expected unique non-learner voting members' fail
run_case identity-mismatch 'exact Machine UUID to Kubernetes node mapping' fail
run_case disconnected 'is not connected in Omni' fail
run_case peer-disconnected 'is not connected in Omni' fail
run_case config-stale 'is not config-current in Omni' fail
run_case initially-cordoned 'must be schedulable before this operation' fail
run_case unexpected-memory '' fail
# Failure-path fencing and bounded recovery.
run_case config-apply-failed '' fail
assert_no_log "$CALL_LOG" 'kubectl:(cordon|drain|uncordon)'
run_case drain-failed 'RECOVERY: restored schedulability' fail
assert_in_order "$CALL_LOG" 'kubectl:cordon unraid-lab-control-planes-6rrw7n' 'kubectl:drain unraid-lab-control-planes-6rrw7n --ignore-daemonsets --delete-emptydir-data --timeout=10m' 'kubectl:uncordon unraid-lab-control-planes-6rrw7n'
run_case remote-shutdown-failed 'RECOVERY: restored schedulability' fail
assert_no_log "$CALL_LOG" 'virsh:(setmaxmem|setmem|start)'
assert_log "$CALL_LOG" 'kubectl:uncordon unraid-lab-control-planes-6rrw7n'
run_case mutation-uuid-mismatch 'domain UUID does not match Omni Machine UUID' fail
assert_in_order "$CALL_LOG" 'rtk:ssh frigate-unraid:preflight' 'rtk:ssh frigate-unraid:mutate' 'virsh:dominfo unraid-lab-control-planes-6rrw7n' 'kubectl:uncordon unraid-lab-control-planes-6rrw7n'
assert_no_log "$CALL_LOG" 'virsh:(shutdown|setmaxmem|setmem|start)'
run_case remote-setmaxmem-failed 'RECOVERY: restored schedulability' fail
assert_in_order "$CALL_LOG" 'virsh:shutdown unraid-lab-control-planes-6rrw7n' 'virsh:setmaxmem unraid-lab-control-planes-6rrw7n 7168 --config --size MiB' 'virsh:start unraid-lab-control-planes-6rrw7n' 'kubectl:uncordon unraid-lab-control-planes-6rrw7n'
assert_no_log "$CALL_LOG" 'virsh:setmem'
run_case remote-setmem-failed 'RECOVERY: restored schedulability' fail
assert_in_order "$CALL_LOG" 'virsh:setmem unraid-lab-control-planes-6rrw7n 7168 --config --size MiB' 'virsh:start unraid-lab-control-planes-6rrw7n' 'kubectl:uncordon unraid-lab-control-planes-6rrw7n'
run_case remote-start-failed 'RECOVERY: restored schedulability' fail
assert_in_order "$CALL_LOG" 'virsh:start unraid-lab-control-planes-6rrw7n' 'virsh:start unraid-lab-control-planes-6rrw7n' 'kubectl:uncordon unraid-lab-control-planes-6rrw7n'
run_case post-wait-failed 'RECOVERY: restored schedulability' fail
run_case placement-failed 'RECOVERY REQUIRED: exact target is not Ready with intended placement' fail
assert_no_log "$CALL_LOG" 'kubectl:uncordon unraid-lab-control-planes-6rrw7n'
run_case final-status-failed 'RECOVERY: restored schedulability' fail
run_case uncordon-failed 'exact target is Ready but uncordon failed' fail
printf 'resize-unraid-imp-control-plane guarded preflight tests passed\n'
