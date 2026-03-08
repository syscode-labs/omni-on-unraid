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

env_args=()
for v in TF_REPLACE_DOMAIN TF_AUTO_APPROVE TF_VAR_libvirt_uri TF_VAR_base_image_path TF_VAR_network_bridge TF_VAR_ssh_public_key TF_VAR_tailscale_authkey TF_VAR_tailscale_hostname; do
  if [ -n "${!v:-}" ]; then
    env_args+=( -e "$v=${!v}" )
  fi
done

docker_flags=(--rm)
if [ -t 0 ] && [ -t 1 ]; then
  docker_flags+=( -it )
else
  docker_flags+=( -i )
fi

docker run "${docker_flags[@]}" \
  "${env_args[@]}" \
  -v "$ROOT_DIR:/workspace" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -v "$HOME:$HOME:ro" \
  -w /workspace \
  "$IMAGE" "$cmd"
