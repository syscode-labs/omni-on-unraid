#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="omni-ops-tools:latest"

build_image() {
  docker build -t "$IMAGE" "$ROOT_DIR/tools/ops-container"
}

# Build image if missing.
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  build_image
fi

if [ $# -eq 0 ]; then
  cmd="/bin/bash"
else
  cmd="$*"
fi

docker run --rm -it \
  -v "$ROOT_DIR:/workspace" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -v "$HOME:$HOME:ro" \
  -w /workspace \
  "$IMAGE" "$cmd"
