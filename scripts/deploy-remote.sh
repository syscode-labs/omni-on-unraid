#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
fi

SSH_USER="${OMNI_SSH_USER:-omni}"
TARGET="${OMNI_SSH_TARGET:-}"
REMOTE_DIR="${OMNI_REMOTE_DIR:-/opt/omni}"
VM_NAME="${OMNI_VM_NAME:-omni-vm}"
JUMP_HOST="${OMNI_LIBVIRT_IMAGE_SSH_TARGET:-}"
JUMP_STAGE_DIR="${OMNI_JUMP_STAGE_DIR:-/tmp/omni-deploy-src}"
RELAY_IP_PREFIXES="${OMNI_DEPLOY_RELAY_IP_PREFIXES:-192.168.122.}"
BASE_SSH_OPTS="${OMNI_SSH_OPTS:--o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5}"

SSH_IDENTITY_FILE="${OMNI_SSH_IDENTITY_FILE:-}"
if [ -z "$SSH_IDENTITY_FILE" ] && [ -n "${OMNI_SSH_PUBLIC_KEY_PATH:-}" ]; then
  candidate="${OMNI_SSH_PUBLIC_KEY_PATH%.pub}"
  if [ -f "$candidate" ]; then
    SSH_IDENTITY_FILE="$candidate"
  fi
fi
if [ -n "$SSH_IDENTITY_FILE" ]; then
  BASE_SSH_OPTS="$BASE_SSH_OPTS -i $SSH_IDENTITY_FILE -o IdentitiesOnly=yes"
fi

if [ -z "$TARGET" ]; then
  libvirt_uri="${OMNI_LIBVIRT_URI:-}"
  if [ -z "$libvirt_uri" ] && [ -n "$JUMP_HOST" ]; then
    libvirt_host="${JUMP_HOST#*@}"
    libvirt_uri="qemu+tcp://${libvirt_host}/system"
  fi

  if [ -n "$libvirt_uri" ]; then
    for _ in $(seq 1 30); do
      ip="$(virsh -c "$libvirt_uri" domifaddr "$VM_NAME" --source lease 2>/dev/null | awk '/ipv4/ {split($4,a,"/"); if (a[1] !~ /^127\./) {print a[1]; exit}}')"
      if [ -z "$ip" ]; then
        ip="$(virsh -c "$libvirt_uri" domifaddr "$VM_NAME" --source agent 2>/dev/null | awk '/ipv4/ {split($4,a,"/"); if ($1 != "lo" && $1 != "docker0" && $1 != "tailscale0" && a[1] !~ /^127\./ && a[1] !~ /^172\.17\./) {print a[1]; exit}}')"
      fi
      if [ -n "$ip" ]; then
        TARGET="${SSH_USER}@${ip}"
        break
      fi
      sleep 5
    done
  fi
fi

if [ -z "$TARGET" ]; then
  echo "Could not resolve VM IP from libvirt leases" >&2
  echo "Set OMNI_SSH_TARGET explicitly in .env (for example: omni@<vm-ip>)" >&2
  exit 1
fi

EXCLUDES=(
  --exclude '.git'
  --exclude '.terraform'
  --exclude 'terraform/libvirt/.terraform'
  --exclude 'terraform/libvirt/*.tfstate*'
  --exclude 'generated'
)

# For configured target IP prefixes, relay through libvirt host instead of ProxyJump.
needs_relay=0
if [ -n "$JUMP_HOST" ] && [ -n "$RELAY_IP_PREFIXES" ]; then
  target_host="${TARGET##*@}"
  IFS=',' read -r -a relay_prefixes <<< "$RELAY_IP_PREFIXES"
  for relay_prefix in "${relay_prefixes[@]}"; do
    relay_prefix="$(echo "$relay_prefix" | tr -d '[:space:]')"
    if [ -n "$relay_prefix" ] && [[ "$target_host" == ${relay_prefix}* ]]; then
      needs_relay=1
      break
    fi
  done
fi

if [ "$needs_relay" = "1" ]; then
  rsync -az --delete \
    -e "ssh $BASE_SSH_OPTS" \
    "${EXCLUDES[@]}" \
    "${ROOT_DIR}/" "${JUMP_HOST}:${JUMP_STAGE_DIR}/"

  ssh -A $BASE_SSH_OPTS "$JUMP_HOST" bash -s -- "$TARGET" "$REMOTE_DIR" "$JUMP_STAGE_DIR" <<'REMOTE'
set -euo pipefail
TARGET="$1"
REMOTE_DIR="$2"
STAGE_DIR="$3"
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

for _ in $(seq 1 60); do
  if ssh $SSH_OPTS "$TARGET" 'echo ok' >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

if ! ssh $SSH_OPTS "$TARGET" 'echo ok' >/dev/null 2>&1; then
  echo "SSH is not reachable on target from jump host: $TARGET" >&2
  exit 1
fi

rsync -az --delete \
  -e "ssh $SSH_OPTS" \
  --exclude '.git' \
  --exclude '.terraform' \
  --exclude 'terraform/libvirt/.terraform' \
  --exclude 'terraform/libvirt/*.tfstate*' \
  --exclude 'generated' \
  "${STAGE_DIR}/" "${TARGET}:${REMOTE_DIR}/"

ssh $SSH_OPTS "$TARGET" "cd '${REMOTE_DIR}' && ./scripts/render.sh && ./scripts/up.sh"
REMOTE

  exit 0
fi

for _ in $(seq 1 30); do
  if ssh $BASE_SSH_OPTS "$TARGET" 'echo ok' >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

if ! ssh $BASE_SSH_OPTS "$TARGET" 'echo ok' >/dev/null 2>&1; then
  echo "SSH is not reachable on target: $TARGET" >&2
  exit 1
fi

rsync -az --delete \
  -e "ssh $BASE_SSH_OPTS" \
  "${EXCLUDES[@]}" \
  "${ROOT_DIR}/" "${TARGET}:${REMOTE_DIR}/"

ssh $BASE_SSH_OPTS "$TARGET" "cd '${REMOTE_DIR}' && ./scripts/render.sh && ./scripts/up.sh"
