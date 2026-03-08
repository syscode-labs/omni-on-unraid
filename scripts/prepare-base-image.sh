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
OMNI_BASE_IMAGE_PATH="${OMNI_BASE_IMAGE_PATH:?set OMNI_BASE_IMAGE_PATH in .env}"
LIBVIRT_TARGET="${OMNI_LIBVIRT_IMAGE_SSH_TARGET:-}"

if [ -n "$LIBVIRT_TARGET" ]; then
  ssh "$LIBVIRT_TARGET" "mkdir -p '$(dirname "$OMNI_BASE_IMAGE_PATH")'"
  ssh "$LIBVIRT_TARGET" "if [ ! -f '$OMNI_BASE_IMAGE_PATH' ]; then curl -fL '$OMNI_BASE_IMAGE_URL' -o '$OMNI_BASE_IMAGE_PATH'; fi"
  ssh "$LIBVIRT_TARGET" "ls -lh '$OMNI_BASE_IMAGE_PATH'"
  echo "Prepared base image on libvirt host via SSH target ${LIBVIRT_TARGET}"
else
  mkdir -p "$(dirname "$OMNI_BASE_IMAGE_PATH")"
  if [ ! -f "$OMNI_BASE_IMAGE_PATH" ]; then
    curl -fL "$OMNI_BASE_IMAGE_URL" -o "$OMNI_BASE_IMAGE_PATH"
  fi
  ls -lh "$OMNI_BASE_IMAGE_PATH"
  echo "Prepared base image on local filesystem"
fi
