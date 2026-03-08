#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="omni-ops-tools:latest"

# Build tools image if missing.
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker build -t "$IMAGE" "$ROOT_DIR/tools/ops-container"
fi

cmd="${*:-/bin/bash}"

docker run --rm -it \
  -v "$ROOT_DIR:/workspace" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -w /workspace \
  "$IMAGE" "$cmd"
