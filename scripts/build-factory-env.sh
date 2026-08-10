#!/usr/bin/env bash
set -euo pipefail

# Build generated/image-factory/factory.env from .env — the interpolated env
# for the factory compose stack. The VM's root-owned /opt/omni/.env is not
# readable by the omni user, mirroring the main stack's generated/compose.env.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
OUT_DIR="${ROOT_DIR}/generated/image-factory"
OUT_ENV="${OUT_DIR}/factory.env"

mkdir -p "$OUT_DIR"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
fi

write_var() {
  local name="$1"
  local value="${!name:-}"
  if [ -n "$value" ]; then
    printf '%s=%s\n' "$name" "$value" >>"$OUT_ENV"
  fi
}

: >"$OUT_ENV"

write_var OMNI_IMAGE_FACTORY_TAG
write_var OMNI_IMAGE_FACTORY_TS_TAG
write_var OMNI_IMAGE_FACTORY_LOG_LEVEL
write_var OMNI_IMAGE_FACTORY_SIGNING_KEY_FILE
write_var OMNI_IMAGE_FACTORY_COSIGN_PUBLIC_KEY_FILE
write_var OMNI_IMAGE_FACTORY_DOCKER_CONFIG
write_var OMNI_IMAGE_FACTORY_GITHUB_TOKEN
write_var OMNI_IMAGE_FACTORY_TS_AUTHKEY
write_var TS_ADVERTISE_TAGS

chmod 600 "$OUT_ENV"
echo "Wrote ${OUT_ENV}"