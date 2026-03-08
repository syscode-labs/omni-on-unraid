#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
fi

default_target="${OMNI_SSH_USER:-omni}@${OMNI_TAILSCALE_HOSTNAME:-omni}"
TARGET="${OMNI_SSH_TARGET:-$default_target}"
REMOTE_DIR="${OMNI_REMOTE_DIR:-/opt/omni}"

rsync -az --delete \
  --exclude '.git' \
  --exclude '.terraform' \
  --exclude 'terraform/libvirt/.terraform' \
  --exclude 'terraform/libvirt/*.tfstate*' \
  --exclude 'generated' \
  "${ROOT_DIR}/" "${TARGET}:${REMOTE_DIR}/"

ssh "${TARGET}" "cd '${REMOTE_DIR}' && ./scripts/render.sh && ./scripts/up.sh"
