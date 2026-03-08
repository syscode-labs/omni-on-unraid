#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
OUT_DIR="${ROOT_DIR}/generated"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
fi

OMNI_VERSION="${OMNI_VERSION:-v1.5.8}"
mkdir -p "$OUT_DIR"

base_url="https://raw.githubusercontent.com/siderolabs/omni/${OMNI_VERSION}/deploy"

curl -fsSL "${base_url}/compose.yaml" -o "${OUT_DIR}/compose.yaml"
curl -fsSL "${base_url}/env.template" -o "${OUT_DIR}/upstream.env.template"

if [ ! -f "$ENV_FILE" ]; then
  cp "${ROOT_DIR}/templates/omni.env.example" "$ENV_FILE"
  echo "Created ${ENV_FILE}; edit it and re-run render" >&2
fi

echo "Rendered Omni deployment assets to ${OUT_DIR} from ${OMNI_VERSION}"
