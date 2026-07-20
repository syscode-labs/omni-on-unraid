#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
fi

output="${OMNI_IMAGE_FACTORY_DOCKER_CONFIG_FILE:-${ROOT_DIR}/generated/connectors/github-app/ghcr-config.json}"
registry="${OMNI_IMAGE_FACTORY_REGISTRY:-ghcr.io}"
permissions="${OMNI_IMAGE_FACTORY_GITHUB_APP_PERMISSIONS:-{\"packages\":\"write\",\"contents\":\"read\",\"metadata\":\"read\"}}"
repositories="${OMNI_IMAGE_FACTORY_GITHUB_APP_REPOSITORIES:-}"

mkdir -p "$(dirname "$output")"

go run ./cmd/github-app-token \
  --output docker-config \
  --output-file "$output" \
  --registry "$registry" \
  --repositories "$repositories" \
  --permissions "$permissions"

echo "Wrote GitHub App Docker config to ${output}"
