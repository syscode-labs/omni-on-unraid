#!/usr/bin/env bash
set -euo pipefail

# Reboot lab nodes that have been NotReady too long (datapath rot watchdog).
#
# Background (2026-08-25): unraid-lab-control-planes-hv297m sat NotReady for
# hours while its kernel stayed alive (Omni SideroLink remained connected) —
# no component in the stack reboots a sick-but-not-crashed node, and the imp
# operator stranded on it crashlooped for two hours before k8s's default 5min
# taint eviction finally moved it. This watchdog closes that gap.
#
# Detection : node Ready!=True and lastHeartbeatTime older than NOT_READY_SECS.
# Action    : omnictl talosconfig + talosctl reboot on the machine's SideroLink
#             address. Guardrails: DRY_RUN default, per-machine cooldown,
#             max reboots per hour, everything logged to stdout (journal).
#
# Env vars: WATCHDOG_DRY_RUN (default true), NOT_READY_SECS (default 360),
#           COOLDOWN_SECS (3600), MAX_REBOOTS_PER_HOUR (2), CLUSTER_NODES
#           (optional space-separated allowlist of node names).

DRY_RUN="${WATCHDOG_DRY_RUN:-true}"
NOT_READY_SECS="${NOT_READY_SECS:-360}"
COOLDOWN_SECS="${COOLDOWN_SECS:-3600}"
MAX_REBOOTS="${MAX_REBOOTS_PER_HOUR:-2}"
ALLOWLIST="${CLUSTER_NODES:-}"

STATE_DIR="${STATE_DIR:-/var/lib/imp-node-watchdog}"
mkdir -p "$STATE_DIR"

log() { echo "$(date -u +%FT%TZ) $*"; }

now() { date +%s; }

# --- resolve nodes ---------------------------------------------------------
nodes_json="$(kubectl get nodes -o json)"
mapfile -t candidates < <(echo "$nodes_json" | jq -r "
  .items[]
  | select(any(.status.conditions[];
        .type==\"Ready\" and .status!=\"True\"))
  | select(.metadata.name | if \"$ALLOWLIST\" == \"\" then true else
      test(\"^($ALLOWLIST)\$\") end)
  | (.metadata.name + \" \" + (
      [.status.conditions[] | select(.type==\"Ready\").lastHeartbeatTime] | first // \"\")
    + \" \" + ([.status.addresses[] | select(.type==\"InternalIP\").address] | first // \"\"))
")

if [ "${#candidates[@]}" -eq 0 ] || [ -z "${candidates[0]}" ]; then
  log "OK: no NotReady nodes"
  exit 0
fi

# --- omni side: machine id + siderolink address per hostname ---------------

reboot_machine() {
  local node="$1" addr="$2"
  local stamp_file="$STATE_DIR/$node.last"
  local now_s; now_s="$(now)"

  # cooldown
  if [ -f "$stamp_file" ]; then
    local last; last="$(cat "$stamp_file")"
    if (( now_s - last < COOLDOWN_SECS )); then
      log "SKIP $node: cooldown ($((now_s - last))s < ${COOLDOWN_SECS}s)"
      return 0
    fi
  fi

  # hourly cap
  local recent
  recent=$(find "$STATE_DIR" -name '*.last' -mmin -60 | wc -l)
  if (( recent >= MAX_REBOOTS )); then
    log "SKIP $node: hourly cap reached ($recent >= $MAX_REBOOTS)"
    return 0
  fi

  if [ "$DRY_RUN" = "true" ]; then
    log "DRY-RUN would reboot $node ($addr) — NotReady > ${NOT_READY_SECS}s"
    return 0
  fi

  log "REBOOTING $node ($addr)"
  local tc="$STATE_DIR/talosconfig"
  ${OMNICTL:-omnictl} talosconfig --output "$tc" >/dev/null
  talosctl --talosconfig "$tc" --nodes "$addr" --cmdline-timeout 30s reboot
  echo "$now_s" > "$stamp_file"
  log "DONE reboot issued for $node"
}

for entry in "${candidates[@]}"; do
  [ -z "$entry" ] && continue
  node="${entry%% *}"
  rest="${entry#* }"
  hb="${rest%% *}"
  addr="${rest##* }"

  # heartbeat age check
  hb_epoch=0
  [ -n "$hb" ] && hb_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$hb" +%s 2>/dev/null \
    || date -d "$hb" +%s 2>/dev/null || echo 0)
  age=$(( $(now) - hb_epoch ))
  if (( hb_epoch == 0 || age < NOT_READY_SECS )); then
    log "WAIT $node: NotReady but heartbeat fresh (age=${age}s < ${NOT_READY_SECS}s)"
    continue
  fi

  if [ -z "$addr" ]; then
    log "ERROR $node: no InternalIP on node status — investigate manually"
    continue
  fi

  reboot_machine "$node" "$addr"
done
