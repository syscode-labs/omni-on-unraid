#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env (copy templates/omni.env.example .env)" >&2
  exit 1
fi

# shellcheck disable=SC1090,SC1091
source "$ENV_FILE"

OMNI_BASE_IMAGE_URL="${OMNI_BASE_IMAGE_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}"
LOCAL_BASE_IMAGE_PATH="${OMNI_LOCAL_BASE_IMAGE_PATH:-${ROOT_DIR}/.cache/images/ubuntu-noble-cloudimg-amd64.qcow2}"
REMOTE_BASE_IMAGE_PATH="${OMNI_BASE_IMAGE_PATH:-}"
LIBVIRT_TARGET="${OMNI_LIBVIRT_IMAGE_SSH_TARGET:-}"

mkdir -p "$(dirname "$LOCAL_BASE_IMAGE_PATH")"
if [ ! -f "$LOCAL_BASE_IMAGE_PATH" ]; then
  curl -fL "$OMNI_BASE_IMAGE_URL" -o "$LOCAL_BASE_IMAGE_PATH"
fi
ls -lh "$LOCAL_BASE_IMAGE_PATH"
echo "Prepared local base image for Terraform at ${LOCAL_BASE_IMAGE_PATH}"

if [ -n "$LIBVIRT_TARGET" ] && [ -n "$REMOTE_BASE_IMAGE_PATH" ]; then
  ssh "$LIBVIRT_TARGET" "mkdir -p '$(dirname "$REMOTE_BASE_IMAGE_PATH")'"
  if ! ssh "$LIBVIRT_TARGET" "test -f '$REMOTE_BASE_IMAGE_PATH'"; then
    scp "$LOCAL_BASE_IMAGE_PATH" "$LIBVIRT_TARGET:$REMOTE_BASE_IMAGE_PATH"
  fi
  ssh "$LIBVIRT_TARGET" "ls -lh '$REMOTE_BASE_IMAGE_PATH'"
  echo "Prepared remote base image copy on libvirt host at ${REMOTE_BASE_IMAGE_PATH}"
fi
