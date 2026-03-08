#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/generated/compose.yaml"
ENV_FILE="${ROOT_DIR}/generated/compose.env"

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Missing ${COMPOSE_FILE}; run ./scripts/render.sh first" >&2
  exit 1
fi

compose_cmd=(docker compose)
if ! docker info >/dev/null 2>&1; then
  if sudo -n docker info >/dev/null 2>&1; then
    compose_cmd=(sudo docker compose)
  fi
fi

"${compose_cmd[@]}" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
