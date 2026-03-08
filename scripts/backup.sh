#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
fi

DATA_DIR="${OMNI_DATA_DIR:-${ROOT_DIR}/data}"
OUT_DIR="${ROOT_DIR}/backups"
mkdir -p "$OUT_DIR"

stamp="$(date +%Y%m%d-%H%M%S)"
out_file="${OUT_DIR}/omni-data-${stamp}.tar.gz"

tar -czf "$out_file" -C "$DATA_DIR" .
echo "Backup written: ${out_file}"
