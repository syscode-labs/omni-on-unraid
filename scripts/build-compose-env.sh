#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
OUT_DIR="${ROOT_DIR}/generated"
OUT_ENV="${OUT_DIR}/compose.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
fi

OMNI_VERSION="${OMNI_VERSION:-v1.5.8}"
OMNI_DOMAIN="${OMNI_DOMAIN:-omni.local}"
DATA_DIR="${OMNI_DATA_DIR:-${ROOT_DIR}/data}"
ABS_DATA_DIR=""
for candidate in "$DATA_DIR" "${ROOT_DIR}/data" "${HOME}/.local/share/omni"; do
  if mkdir -p "$candidate" >/dev/null 2>&1; then
    ABS_DATA_DIR="$(cd "$candidate" && pwd)"
    break
  fi
done
if [ -z "$ABS_DATA_DIR" ]; then
  echo "Could not create writable data directory (checked: $DATA_DIR, ${ROOT_DIR}/data, ${HOME}/.local/share/omni)" >&2
  exit 1
fi

ETCD_DIR="${ABS_DATA_DIR}/etcd"
TLS_DIR="${ABS_DATA_DIR}/tls"
ENC_KEY="${ABS_DATA_DIR}/omni.asc"
ACCOUNT_FILE="${ABS_DATA_DIR}/omni-account-uuid"
CERT_FILE="${TLS_DIR}/tls.crt"
KEY_FILE="${TLS_DIR}/tls.key"

mkdir -p "$OUT_DIR" "$ETCD_DIR" "$TLS_DIR"

if [ ! -f "$ENC_KEY" ]; then
  openssl rand -base64 32 > "$ENC_KEY"
fi

if [ ! -f "$ACCOUNT_FILE" ]; then
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen > "$ACCOUNT_FILE"
  else
    cat /proc/sys/kernel/random/uuid > "$ACCOUNT_FILE"
  fi
fi
OMNI_ACCOUNT_UUID="$(tr -d '\r\n' < "$ACCOUNT_FILE")"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -days 3650 \
    -subj "/CN=${OMNI_DOMAIN}" >/dev/null 2>&1
fi

OMNI_IMG_TAG="${OMNI_IMG_TAG:-${OMNI_VERSION}}"
NAME="${OMNI_NAME:-omni}"
EVENT_SINK_PORT="${OMNI_EVENT_SINK_PORT:-8091}"
BIND_ADDR="${OMNI_BIND_ADDR:-0.0.0.0:443}"
MACHINE_API_BIND_ADDR="${OMNI_MACHINE_API_BIND_ADDR:-0.0.0.0:8090}"
K8S_PROXY_BIND_ADDR="${OMNI_K8S_PROXY_BIND_ADDR:-0.0.0.0:8100}"
ADVERTISED_API_URL="${OMNI_ADVERTISED_API_URL:-https://${OMNI_DOMAIN}}"
ADVERTISED_K8S_PROXY_URL="${OMNI_ADVERTISED_K8S_PROXY_URL:-https://${OMNI_DOMAIN}:8100/}"
SIDEROLINK_ADVERTISED_API_URL="${OMNI_SIDEROLINK_API_URL:-https://${OMNI_DOMAIN}:8090/}"
SIDEROLINK_WIREGUARD_ADVERTISED_ADDR="${OMNI_WG_ADDR:-${OMNI_DOMAIN}:50180}"
INITIAL_USER_EMAILS="${OMNI_INITIAL_USER_EMAILS:-${OMNI_ADMIN_EMAIL:-admin@${OMNI_DOMAIN}}}"
AUTH="${OMNI_AUTH_ARGS:-}"
OMNI_STORAGE_KIND="${OMNI_STORAGE_KIND:-boltdb}"
OMNI_STORAGE_SQLITE_PATH="${OMNI_STORAGE_SQLITE_PATH:-/_out/omni.sqlite}"
OMNI_EXTRA_ARGS_DEFAULT="--storage-kind=${OMNI_STORAGE_KIND} --sqlite-storage-path=${OMNI_STORAGE_SQLITE_PATH}"
OMNI_EXTRA_ARGS="${OMNI_EXTRA_ARGS:-$OMNI_EXTRA_ARGS_DEFAULT}"

AUTH_TRIMMED="$(echo "${AUTH}" | tr -d '[:space:]')"
if [ -z "$AUTH_TRIMMED" ]; then
  echo "OMNI_AUTH_ARGS is required. Configure an auth provider (Auth0/OIDC/SAML) in .env." >&2
  exit 1
fi

cat > "$OUT_ENV" <<EOV
OMNI_IMG_TAG=${OMNI_IMG_TAG}
OMNI_ACCOUNT_UUID=${OMNI_ACCOUNT_UUID}
NAME=${NAME}
EVENT_SINK_PORT=${EVENT_SINK_PORT}
TLS_CERT=${CERT_FILE}
TLS_KEY=${KEY_FILE}
ETCD_VOLUME_PATH=${ETCD_DIR}
ETCD_ENCRYPTION_KEY=${ENC_KEY}
BIND_ADDR=${BIND_ADDR}
MACHINE_API_BIND_ADDR=${MACHINE_API_BIND_ADDR}
K8S_PROXY_BIND_ADDR=${K8S_PROXY_BIND_ADDR}
ADVERTISED_API_URL=${ADVERTISED_API_URL}
ADVERTISED_K8S_PROXY_URL=${ADVERTISED_K8S_PROXY_URL}
SIDEROLINK_ADVERTISED_API_URL=${SIDEROLINK_ADVERTISED_API_URL}
SIDEROLINK_WIREGUARD_ADVERTISED_ADDR=${SIDEROLINK_WIREGUARD_ADVERTISED_ADDR}
INITIAL_USER_EMAILS=${INITIAL_USER_EMAILS}
AUTH=${AUTH} ${OMNI_EXTRA_ARGS}
EOV

echo "Wrote ${OUT_ENV}"
