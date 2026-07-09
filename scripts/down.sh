#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/generated/compose.yaml"
ENV_FILE="${ROOT_DIR}/generated/compose.env"
OVERRIDE_FILE="${ROOT_DIR}/templates/compose.caddy.override.yaml"

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Missing ${COMPOSE_FILE}; run ./scripts/render.sh first" >&2
  exit 1
fi

# shellcheck disable=SC1090,SC1091
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

compose_cmd=(docker compose)
if ! docker info >/dev/null 2>&1; then
  if sudo -n docker info >/dev/null 2>&1; then
    compose_cmd=(sudo docker compose)
  fi
fi

compose_files=(-f "$COMPOSE_FILE")
if [ -f "$OVERRIDE_FILE" ]; then
  compose_files+=(-f "$OVERRIDE_FILE")
fi

if [ "${TLS_MODE:-direct}" = "caddy-sni" ]; then
  export COMPOSE_PROFILES="caddy-sni"
fi

"${compose_cmd[@]}" "${compose_files[@]}" --env-file "$ENV_FILE" down
