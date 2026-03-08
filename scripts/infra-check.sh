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

required=(OMNI_BASE_IMAGE_PATH OMNI_SSH_PUBLIC_KEY_PATH)
for key in "${required[@]}"; do
  if [ -z "${!key:-}" ]; then
    echo "Missing required .env value: ${key}" >&2
    exit 1
  fi
done

if [ ! -f "$OMNI_SSH_PUBLIC_KEY_PATH" ]; then
  echo "SSH public key file not found: $OMNI_SSH_PUBLIC_KEY_PATH" >&2
  exit 1
fi

echo "$OMNI_BASE_IMAGE_PATH" | grep -q '^/' || {
  echo "OMNI_BASE_IMAGE_PATH must be an absolute path" >&2
  exit 1
}

echo "Infra preflight passed"
