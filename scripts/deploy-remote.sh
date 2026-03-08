#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${OMNI_SSH_TARGET:?set OMNI_SSH_TARGET (e.g. omni@100.x.y.z)}"
REMOTE_DIR="${OMNI_REMOTE_DIR:-/opt/omni}"

rsync -az --delete \
  --exclude '.git' \
  --exclude '.terraform' \
  --exclude 'terraform/libvirt/.terraform' \
  --exclude 'terraform/libvirt/*.tfstate*' \
  "${ROOT_DIR}/" "${TARGET}:${REMOTE_DIR}/"

ssh "${TARGET}" "cd '${REMOTE_DIR}' && ./scripts/render.sh && ./scripts/up.sh"
