#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/generated/compose.yaml"
ENV_FILE="${ROOT_DIR}/.env"

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Missing ${COMPOSE_FILE}; run ./scripts/render.sh first" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing ${ENV_FILE}; copy templates/omni.env.example and edit it" >&2
  exit 1
fi

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
