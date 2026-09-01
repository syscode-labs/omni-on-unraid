#!/usr/bin/env bash
set -euo pipefail

# Bring up the on-prem Image Factory on a remote host.
#   - renders generated/image-factory/config.yaml locally (Go is required)
#   - provisions cache-signing.key + cosign.pub from Bitwarden (optional
#     wrapper; callers that pre-provision can set OMNI_FACTORY_SKIP_KEYS=1)
#   - copies the generated config + keys to the remote before the compose
#     secrets become unreadable (they live under generated/ which the main
#     rsync excludes)
#   - runs `docker compose up -d` on the remote factory stack

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
fi

TARGET="${OMNI_SSH_TARGET:-}"
REMOTE_DIR="${OMNI_REMOTE_DIR:-/opt/omni}"
SSH_USER="${OMNI_SSH_USER:-omni}"
SSH_OPTS="${OMNI_SSH_OPTS:--o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5}"
if [ -n "${OMNI_SSH_IDENTITY_FILE:-}" ]; then
  SSH_OPTS="$SSH_OPTS -i $OMNI_SSH_IDENTITY_FILE -o IdentitiesOnly=yes"
fi

if [ -z "$TARGET" ]; then
  TARGET="${SSH_USER}@omni.wind-bearded.ts.net"
fi

if [ "${OMNI_FACTORY_SKIP_KEYS:-0}" != "1" ]; then
  "${ROOT_DIR}/scripts/provision-factory-keys.sh"
fi

echo "Rendering image-factory config"
mise exec -- go run ./cmd/omni-render image-factory-config --output "${ROOT_DIR}/generated/image-factory/config.yaml"
"${ROOT_DIR}/scripts/build-factory-env.sh"

echo "Copying factory stack to ${TARGET}:${REMOTE_DIR}/generated/image-factory/"
# The first deployment may create this path through sudo; restore ownership so
# later deployments can update generated factory inputs without manual cleanup.
ssh $SSH_OPTS "$TARGET" "sudo -n mkdir -p '${REMOTE_DIR}/generated/image-factory/keys' && sudo -n chown -R '${SSH_USER}:${SSH_USER}' '${REMOTE_DIR}/generated/image-factory'"
scp $SSH_OPTS "${ROOT_DIR}/omni/image-factory/docker-compose.yml" "${TARGET}:${REMOTE_DIR}/generated/image-factory/docker-compose.yml"
scp $SSH_OPTS "${ROOT_DIR}/omni/image-factory/serve.json" "${TARGET}:${REMOTE_DIR}/generated/image-factory/serve.json"
scp $SSH_OPTS "${ROOT_DIR}/generated/image-factory/config.yaml" "${TARGET}:${REMOTE_DIR}/generated/image-factory/config.yaml"
scp $SSH_OPTS "${ROOT_DIR}/generated/image-factory/factory.env" "${TARGET}:${REMOTE_DIR}/generated/image-factory/factory.env"
scp $SSH_OPTS "${ROOT_DIR}/generated/image-factory/keys/cache-signing.key" "${TARGET}:${REMOTE_DIR}/generated/image-factory/keys/cache-signing.key"
if [ -f "${ROOT_DIR}/generated/image-factory/keys/cosign.pub" ]; then
  scp $SSH_OPTS "${ROOT_DIR}/generated/image-factory/keys/cosign.pub" "${TARGET}:${REMOTE_DIR}/generated/image-factory/keys/cosign.pub"
else
  echo "No cosign.pub generated; connected-mode factory verifies Sidero images keyless (skip)"
fi

echo "Placing stack under ${REMOTE_DIR}/omni/image-factory/ (sudo)"
ssh $SSH_OPTS "$TARGET" "sudo -n mkdir -p '${REMOTE_DIR}/omni/image-factory' && sudo -n cp '${REMOTE_DIR}/generated/image-factory/docker-compose.yml' '${REMOTE_DIR}/omni/image-factory/docker-compose.yml' && sudo -n cp '${REMOTE_DIR}/generated/image-factory/serve.json' '${REMOTE_DIR}/omni/image-factory/serve.json'"

echo "Starting factory stack over SSH"
ssh $SSH_OPTS "$TARGET" "cd '${REMOTE_DIR}' && sudo -n docker compose -f omni/image-factory/docker-compose.yml --env-file generated/image-factory/factory.env up -d --force-recreate image-factory"
