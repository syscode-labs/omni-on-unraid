#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/generated/compose.yaml"
ENV_FILE="${ROOT_DIR}/generated/compose.env"
OVERRIDE_FILE="${ROOT_DIR}/templates/compose.caddy.override.yaml"
RUNNER_OVERRIDE_FILE="${ROOT_DIR}/templates/compose.runner.override.yaml"

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

./scripts/build-compose-env.sh
./scripts/build-caddy-config.sh

# shellcheck disable=SC1090,SC1091
source "$ENV_FILE"

compose_files=(-f "$COMPOSE_FILE")
if [ -f "$OVERRIDE_FILE" ]; then
  # Always include override; Caddy service is gated by compose profile.
  compose_files+=(-f "$OVERRIDE_FILE")
fi
if [ -f "$RUNNER_OVERRIDE_FILE" ]; then
  compose_files+=(-f "$RUNNER_OVERRIDE_FILE")
fi

compose_profile_args=()
if [ "${TLS_MODE:-direct}" = "caddy-sni" ]; then
  compose_profile_args+=(--profile caddy-sni)
fi
if [ "${GITHUB_RUNNER_ENABLED:-false}" = "true" ]; then
  compose_profile_args+=(--profile github-runner)
fi

# Pass profiles as command-line arguments because sudo does not preserve
# COMPOSE_PROFILES from the caller's environment.
"${compose_cmd[@]}" "${compose_files[@]}" "${compose_profile_args[@]}" --env-file "$ENV_FILE" up -d

if [ "${TLS_MODE:-direct}" = "caddy-sni" ]; then
  # Caddy reads a bind-mounted generated Caddyfile, so recreate it to apply changes.
  "${compose_cmd[@]}" "${compose_files[@]}" "${compose_profile_args[@]}" --env-file "$ENV_FILE" up -d --force-recreate caddy
fi
