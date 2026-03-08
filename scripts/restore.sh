#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <backup-tar.gz>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
fi

DATA_DIR="${OMNI_DATA_DIR:-${ROOT_DIR}/data}"
backup_file="$1"

mkdir -p "$DATA_DIR"
rm -rf "${DATA_DIR:?}"/*

tar -xzf "$backup_file" -C "$DATA_DIR"
echo "Restore completed into ${DATA_DIR}"
