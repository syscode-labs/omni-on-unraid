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

# Derive OMNI_LIBVIRT_URI if omitted.
if [ -z "${OMNI_LIBVIRT_URI:-}" ] && [ -n "${OMNI_LIBVIRT_IMAGE_SSH_TARGET:-}" ]; then
  libvirt_host="${OMNI_LIBVIRT_IMAGE_SSH_TARGET#*@}"
  OMNI_LIBVIRT_URI="qemu+tcp://${libvirt_host}/system"
fi

required=(OMNI_BASE_IMAGE_PATH OMNI_SSH_PUBLIC_KEY_PATH)
for key in "${required[@]}"; do
  if [ -z "${!key:-}" ]; then
    echo "Missing required .env value: ${key}" >&2
    exit 1
  fi
done

if [ -z "${OMNI_LIBVIRT_URI:-}" ]; then
  echo "Missing libvirt URI: set OMNI_LIBVIRT_URI or OMNI_LIBVIRT_IMAGE_SSH_TARGET" >&2
  exit 1
fi

if [ ! -f "$OMNI_SSH_PUBLIC_KEY_PATH" ]; then
  echo "SSH public key file not found: $OMNI_SSH_PUBLIC_KEY_PATH" >&2
  exit 1
fi

echo "$OMNI_BASE_IMAGE_PATH" | grep -q '^/' || {
  echo "OMNI_BASE_IMAGE_PATH must be an absolute path" >&2
  exit 1
}

if [[ "$OMNI_LIBVIRT_URI" == qemu:///system ]]; then
  echo "OMNI_LIBVIRT_URI is local qemu:///system; this requires local libvirtd running on your machine" >&2
fi

if [ -n "${OMNI_LIBVIRT_IMAGE_SSH_TARGET:-}" ]; then
  if ! ssh -o BatchMode=yes "$OMNI_LIBVIRT_IMAGE_SSH_TARGET" 'echo ok' >/dev/null 2>&1; then
    echo "SSH connectivity failed for OMNI_LIBVIRT_IMAGE_SSH_TARGET: $OMNI_LIBVIRT_IMAGE_SSH_TARGET" >&2
    echo "Validate manually: ssh -o BatchMode=yes $OMNI_LIBVIRT_IMAGE_SSH_TARGET 'echo ok'" >&2
    exit 1
  fi

  if ! ssh -o BatchMode=yes "$OMNI_LIBVIRT_IMAGE_SSH_TARGET" "test -f '$OMNI_BASE_IMAGE_PATH'"; then
    echo "Base image missing on remote libvirt host: $OMNI_BASE_IMAGE_PATH" >&2
    echo "Run: mise run infra:prepare-image" >&2
    exit 1
  fi
else
  if [ ! -f "$OMNI_BASE_IMAGE_PATH" ]; then
    echo "Base image missing locally: $OMNI_BASE_IMAGE_PATH" >&2
    echo "Run: mise run infra:prepare-image" >&2
    exit 1
  fi
fi

echo "Infra preflight passed"
