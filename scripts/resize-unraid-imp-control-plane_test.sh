#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/resize-unraid-imp-control-plane.sh"
bash -n "$script"
shellcheck -e SC1091 "$script"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.hermes/omni"
printf 'OMNI_ENDPOINT=https://example.invalid\nOMNI_SERVICE_ACCOUNT_KEY=test-only\n' >"$tmp/home/.hermes/omni/omni.env"

cat >"$tmp/bin/mise" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
shift 4 # mise x omnictl@... -- omnictl
case "$1 ${2:-}" in
  'get Machines.omni.sidero.dev')
    cat <<JSON
{"metadata":{"id":"ee285972-e7d5-433e-a67c-efb924707a8c","labels":{"omni.sidero.dev/machine-request":"unraid-lab-control-planes-6rrw7n"}},"spec":{"connected":$( [ "${SCENARIO:-healthy}" = disconnected ] && echo false || echo true )}}
{"metadata":{"id":"1ebbe497-22fc-42a9-8ca9-eaa1f339ea83","labels":{"omni.sidero.dev/machine-request":"unraid-lab-control-planes-ng8qnl"}},"spec":{"connected":true}}
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
  apply\ *) : ;;
  'cluster status') echo 'RUNNING Ready (3/3)' ;;
  *) echo "unexpected omnictl invocation: $*" >&2; exit 2 ;;
esac
MOCK
cat >"$tmp/bin/kubectl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1 $2" = 'get nodes' ]; then
  target='ee285972-e7d5-433e-a67c-efb924707a8c'; [ "${SCENARIO:-healthy}" = identity-mismatch ] && target='00000000-0000-0000-0000-000000000000'
  cat <<JSON
{"items":[{"metadata":{"name":"unraid-lab-control-planes-6rrw7n"},"status":{"nodeInfo":{"systemUUID":"$target"}}},{"metadata":{"name":"unraid-lab-control-planes-ng8qnl"},"status":{"nodeInfo":{"systemUUID":"1ebbe497-22fc-42a9-8ca9-eaa1f339ea83"}}},{"metadata":{"name":"unraid-lab-control-planes-slhjx6"},"status":{"nodeInfo":{"systemUUID":"5db9ed95-99dd-4d05-ab36-57707f4ec92b"}}}]}
JSON
elif [ "$1" = get ] && [ "${2:-}" = --raw=/readyz ]; then
  [ "${SCENARIO:-healthy}" = api-failed ] && exit 1; echo ok
elif [ "$1 ${2:-}" = 'get node' ]; then
  echo '{"metadata":{"labels":{"imp/enabled":"true"}},"spec":{"taints":[{"key":"imp.dev/runner","value":"true","effect":"NoSchedule"}]}}'
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
cat >"$tmp/bin/coding-agent-remote-operations-supervisor" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
if [ "${SCENARIO:-healthy}" = unexpected-memory ]; then
  exit 1
fi
exit 0
MOCK
chmod +x "$tmp/bin"/*

run_case() {
  local scenario="$1" want="$2" expected="$3" preflight="${4:-0}" output status
  set +e
  output="$(PATH="$tmp/bin:$PATH" HOME="$tmp/home" REMOTE_OPS="$tmp/bin/coding-agent-remote-operations-supervisor" APPLY=$((1 - preflight)) PREFLIGHT_ONLY="$preflight" SCENARIO="$scenario" "$script" 2>&1)"
  status=$?
  set -e
  if [ "$expected" = pass ]; then
    [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
  else
    [ "$status" -ne 0 ] || { printf '%s unexpectedly passed\n' "$scenario" >&2; return 1; }
    printf '%s\n' "$output" | grep -Fq "$want" || { printf '%s\n' "$output" >&2; return 1; }
  fi
}

# Both accepted paths.
run_case healthy '' pass
run_case recovery-2of3 '' pass
run_case recovery-2of3 '' pass 1
# Critical rejection gates.
run_case other-unhealthy 'both named peers must be healthy' fail
run_case api-failed 'API /readyz did not succeed' fail
run_case etcd-learner 'three expected unique non-learner voting members' fail
run_case etcd-wrong-member 'three expected unique non-learner voting members' fail
run_case identity-mismatch 'exact Machine UUID to Kubernetes node mapping' fail
run_case disconnected 'is not connected in Omni' fail
run_case config-stale 'is not config-current in Omni' fail
run_case unexpected-memory '' fail
printf 'resize-unraid-imp-control-plane guarded preflight tests passed\n'
