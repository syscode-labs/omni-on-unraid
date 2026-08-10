#!/usr/bin/env bash
set -euo pipefail

# Provision the on-prem Image Factory signing keys into generated/image-factory/keys/
# (gitignored, rsync-excluded). Source of truth is Bitwarden item in the
# Syscode-labs folder. Private cosign key is never written here by default —
# only the files the factory compose mounts (cache-signing.key, cosign.pub).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/generated/image-factory/keys"
BW_ITEM_NAME="${OMNI_IMAGE_FACTORY_BW_ITEM:-OMNI_IMAGE_FACTORY_COSIGN_KEYS}"
INCLUDE_COSIGN_KEY="${OMNI_IMAGE_FACTORY_PROVISION_COSIGN_KEY:-0}"

mkdir -p "$OUT_DIR"

if ! command -v bw >/dev/null 2>&1; then
  echo "bitwarden CLI (bw) not found" >&2
  exit 1
fi

SESSION_ARGS=()
if [ -n "${BW_SESSION:-}" ]; then
  SESSION_ARGS=(--session "$BW_SESSION")
fi

if ! bw status "${SESSION_ARGS[@]}" 2>/dev/null | grep -q '"status":"unlocked"'; then
  echo "Bitwarden vault is locked; run: bw unlock" >&2
  exit 1
fi

ITEM_JSON="$(bw get item "$BW_ITEM_NAME" "${SESSION_ARGS[@]}")"

write_field() {
  local field_name="$1"
  local out_path="$2"
  python3 - "$ITEM_JSON" "$field_name" "$out_path" <<'PYEOF'
import json, sys
item, field, path = json.loads(sys.argv[1]), sys.argv[2], sys.argv[3]
for f in item.get("fields", []):
    if f["name"] == field:
        open(path, "w").write(f["value"])
        sys.exit(0)
sys.exit(1)
PYEOF
}

write_field "cacheSigningKey" "$OUT_DIR/cache-signing.key"
chmod 600 "$OUT_DIR/cache-signing.key"
write_field "cosignPub" "$OUT_DIR/cosign.pub"
chmod 600 "$OUT_DIR/cosign.pub"

if [ "$INCLUDE_COSIGN_KEY" = "1" ]; then
  write_field "cosignKey" "$OUT_DIR/cosign.key"
  chmod 600 "$OUT_DIR/cosign.key"
  echo "cosign.key + cosign.pub + cache-signing.key written to ${OUT_DIR}"
else
  echo "cosign.pub + cache-signing.key written to ${OUT_DIR}"
fi