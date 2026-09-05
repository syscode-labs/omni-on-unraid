#!/usr/bin/env bash
set -euo pipefail

# Resolve the actual provider image through Docker Compose, then inspect that
# exact tag or digest remotely. This deliberately does not pull, run, update,
# or discover a newer image.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_BIN="${DOCKER_BIN:-docker}"
COMPOSE_FILE="${OMNI_PROVIDER_COMPOSE_FILE:-${COMPOSE_FILE:-}}"
ENV_FILE="${OMNI_PROVIDER_ENV_FILE:-$ROOT_DIR/.env}"
PROJECT_DIRECTORY="${OMNI_PROVIDER_PROJECT_DIRECTORY:-$ROOT_DIR}"
CONTAINER="${OMNI_PROVIDER_CONTAINER:-}"
TIMEOUT_SECONDS="${OMNI_PROVIDER_ARTIFACT_TIMEOUT_SECONDS:-20}"
SERVICE="omni-infra-provider-libvirt"

if ! [[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "FATAL: OMNI_PROVIDER_ARTIFACT_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 1
fi

if ! command -v "$DOCKER_BIN" >/dev/null 2>&1; then
  echo "FATAL: Docker CLI not found; cannot verify the configured provider artifact." >&2
  exit 1
fi

if [ -n "$CONTAINER" ]; then
  # The native runner deliberately interrogates the host-owned Compose service
  # rather than resolving a checkout-local Compose project. The label binds
  # the image to the live provider's actual Compose file.
  image="$($DOCKER_BIN inspect --format '{{index .Config.Labels "com.docker.compose.project.config_files"}} {{.Config.Image}}' "$CONTAINER")" || {
    echo "FATAL: Could not inspect the live provider container: $CONTAINER" >&2
    exit 1
  }
  expected_file="${OMNI_PROVIDER_COMPOSE_FILE:?OMNI_PROVIDER_COMPOSE_FILE is required with OMNI_PROVIDER_CONTAINER}"
  case "$image" in
    "$expected_file "*) image="${image#"$expected_file "}" ;;
    *) echo "FATAL: Live provider is not bound to expected Compose file: $expected_file" >&2; exit 1 ;;
  esac
else
  if [ ! -r "$ENV_FILE" ]; then
    echo "FATAL: Provider environment file is not readable: $ENV_FILE" >&2
    exit 1
  fi
  compose_args=(compose --project-directory "$PROJECT_DIRECTORY" --env-file "$ENV_FILE")
  if [ -n "$COMPOSE_FILE" ]; then
    # Preserve a caller's Compose-file override, including a path-separated
    # COMPOSE_FILE value, rather than silently validating the repository default.
    IFS=":" read -r -a compose_files <<<"$COMPOSE_FILE"
    for compose_file in "${compose_files[@]}"; do
      if [ -z "$compose_file" ]; then
        echo "FATAL: OMNI_PROVIDER_COMPOSE_FILE/COMPOSE_FILE contains an empty path." >&2
        exit 1
      fi
      compose_args+=(--file "$compose_file")
    done
  else
    compose_args+=(--file "$ROOT_DIR/omni/provider/docker-compose.yml")
  fi

  if ! image="$($DOCKER_BIN "${compose_args[@]}" config --images "$SERVICE")"; then
    echo "FATAL: Could not resolve the configured $SERVICE image with Docker Compose." >&2
    exit 1
  fi
fi

mapfile -t images < <(printf '%s\n' "$image" | sed '/^[[:space:]]*$/d')
if [ "${#images[@]}" -ne 1 ]; then
  echo "FATAL: Expected exactly one configured image for $SERVICE; resolved ${#images[@]}." >&2
  exit 1
fi
image="${images[0]}"

if python3 - "$TIMEOUT_SECONDS" "$DOCKER_BIN" manifest inspect "$image" <<'PY'
import subprocess
import sys

seconds = int(sys.argv[1])
command = sys.argv[2:]
try:
    completed = subprocess.run(command, timeout=seconds)
except subprocess.TimeoutExpired:
    print(f"FATAL: Timed out after {seconds}s checking configured provider artifact: {command[-1]}", file=sys.stderr)
    sys.exit(124)
sys.exit(completed.returncode)
PY
then
  :
else
  status=$?
  if [ "$status" -eq 124 ]; then
    exit "$status"
  fi
  echo "FATAL: Configured provider artifact is unavailable or inaccessible: $image" >&2
  echo "Check that this exact tag or digest was published and that registry authentication/network access is available." >&2
  exit 1
fi

echo "Configured provider artifact is available: $image"
