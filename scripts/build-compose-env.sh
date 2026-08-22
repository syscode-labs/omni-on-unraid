#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
OUT_DIR="${ROOT_DIR}/generated"
OUT_ENV="${OUT_DIR}/compose.env"
CADDY_DIR="${OUT_DIR}/caddy"
CERTS_DIR="${OUT_DIR}/certs"

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
SECONDARY_STORAGE_DIR="${ABS_DATA_DIR}/secondary-storage"
TLS_DIR="${ABS_DATA_DIR}/tls"
ENC_KEY="${ABS_DATA_DIR}/omni.asc"
ACCOUNT_FILE="${ABS_DATA_DIR}/omni-account-uuid"
CERT_FILE="${TLS_DIR}/tls.crt"
KEY_FILE="${TLS_DIR}/tls.key"

mkdir -p "$OUT_DIR" "$ETCD_DIR" "$SECONDARY_STORAGE_DIR" "$TLS_DIR" "$CADDY_DIR" "$CERTS_DIR"

host_from_url() {
  local rest
  rest="${1#*://}"
  rest="${rest%%/*}"
  rest="${rest##*@}"
  if [[ "$rest" == \[* ]]; then
    rest="${rest#\[}"
    printf '%s\n' "${rest%%\]*}"
  else
    printf '%s\n' "${rest%%:*}"
  fi
}

host_from_addr() {
  local rest="$1"
  if [[ "$rest" == \[* ]]; then
    rest="${rest#\[}"
    printf '%s\n' "${rest%%\]*}"
  else
    printf '%s\n' "${rest%%:*}"
  fi
}

san_entry_for_host() {
  local host="$1"
  if [ -z "$host" ]; then
    return
  fi
  if [[ "$host" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || [[ "$host" == *:* ]]; then
    printf 'IP:%s\n' "$host"
  else
    printf 'DNS:%s\n' "$host"
  fi
}

add_san_entry() {
  local entry="$1"
  local existing
  if [ -z "$entry" ]; then
    return
  fi
  for existing in "${CERT_SAN_ENTRIES[@]}"; do
    if [ "$existing" = "$entry" ]; then
      return
    fi
  done
  CERT_SAN_ENTRIES+=("$entry")
}

cert_has_required_sans() {
  local cert="$1"
  local san_output entry value
  san_output="$(openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null || true)"
  for entry in "${CERT_SAN_ENTRIES[@]}"; do
    case "$entry" in
      DNS:*)
        value="${entry#DNS:}"
        grep -Fq "DNS:${value}" <<< "$san_output" || return 1
        ;;
      IP:*)
        value="${entry#IP:}"
        grep -Fq "IP Address:${value}" <<< "$san_output" || return 1
        ;;
    esac
  done
}

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

DEFAULT_WG_HOST="${OMNI_TS_IP:-${OMNI_DOMAIN}}"
CERT_SIDEROLINK_API_URL="${OMNI_SIDEROLINK_API_URL:-https://${OMNI_DOMAIN}:8090/}"
CERT_WG_ADDR="${OMNI_WG_ADDR:-${DEFAULT_WG_HOST}:50180}"
CERT_SAN_ENTRIES=()
add_san_entry "$(san_entry_for_host "$OMNI_DOMAIN")"
add_san_entry "$(san_entry_for_host "$(host_from_url "$CERT_SIDEROLINK_API_URL")")"
add_san_entry "$(san_entry_for_host "$(host_from_addr "$CERT_WG_ADDR")")"
if [ -n "${OMNI_TLS_EXTRA_SANS:-}" ]; then
  IFS=',' read -r -a extra_sans <<< "$OMNI_TLS_EXTRA_SANS"
  for extra_san in "${extra_sans[@]}"; do
    extra_san="${extra_san#"${extra_san%%[![:space:]]*}"}"
    extra_san="${extra_san%"${extra_san##*[![:space:]]}"}"
    case "$extra_san" in
      DNS:*|IP:*)
        add_san_entry "$extra_san"
        ;;
      *)
        add_san_entry "$(san_entry_for_host "$extra_san")"
        ;;
    esac
  done
fi

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ] || ! cert_has_required_sans "$CERT_FILE"; then
  SAN_CONFIG="$(mktemp)"
  trap 'rm -f "$SAN_CONFIG"' EXIT
  {
    printf '[req]\n'
    printf 'distinguished_name=req_distinguished_name\n'
    printf 'x509_extensions=v3_req\n'
    printf 'prompt=no\n'
    printf '[req_distinguished_name]\n'
    printf 'CN=%s\n' "$OMNI_DOMAIN"
    printf '[v3_req]\n'
    printf 'subjectAltName=%s\n' "$(IFS=','; echo "${CERT_SAN_ENTRIES[*]}")"
  } > "$SAN_CONFIG"

  openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -days 3650 \
    -config "$SAN_CONFIG" \
    -extensions v3_req >/dev/null 2>&1
fi

cp "$CERT_FILE" "${CERTS_DIR}/machine-api.crt"
cp "$KEY_FILE" "${CERTS_DIR}/machine-api.key"
chmod 0644 "${CERTS_DIR}/machine-api.crt"
chmod 0600 "${CERTS_DIR}/machine-api.key"

OMNI_IMG_TAG="${OMNI_IMG_TAG:-${OMNI_VERSION}}"
NAME="${OMNI_NAME:-omni}"
EVENT_SINK_PORT="${OMNI_EVENT_SINK_PORT:-8091}"
TLS_MODE="${OMNI_TLS_MODE:-direct}"
if [ "$TLS_MODE" != "caddy-sni" ]; then
  TLS_MODE="direct"
fi
if [ "$TLS_MODE" = "caddy-sni" ]; then
  BIND_ADDR="${OMNI_BIND_ADDR:-127.0.0.1:8443}"
  MACHINE_API_BIND_ADDR="${OMNI_MACHINE_API_BIND_ADDR:-127.0.0.1:8092}"
  K8S_PROXY_BIND_ADDR="${OMNI_K8S_PROXY_BIND_ADDR:-127.0.0.1:8100}"
else
  BIND_ADDR="${OMNI_BIND_ADDR:-0.0.0.0:443}"
  MACHINE_API_BIND_ADDR="${OMNI_MACHINE_API_BIND_ADDR:-0.0.0.0:8090}"
  K8S_PROXY_BIND_ADDR="${OMNI_K8S_PROXY_BIND_ADDR:-0.0.0.0:8100}"
fi
ADVERTISED_API_URL="${OMNI_ADVERTISED_API_URL:-https://${OMNI_DOMAIN}}"
ADVERTISED_K8S_PROXY_URL="${OMNI_ADVERTISED_K8S_PROXY_URL:-https://${OMNI_DOMAIN}:8100/}"
SIDEROLINK_ADVERTISED_API_URL="${OMNI_SIDEROLINK_API_URL:-https://${OMNI_DOMAIN}:8090/}"
SIDEROLINK_WIREGUARD_ADVERTISED_ADDR="${OMNI_WG_ADDR:-${DEFAULT_WG_HOST}:50180}"
INITIAL_USER_EMAILS="${OMNI_INITIAL_USER_EMAILS:-${OMNI_ADMIN_EMAIL:-admin@${OMNI_DOMAIN}}}"
AUTH="${OMNI_AUTH_ARGS:-}"
OMNI_STORAGE_KIND="${OMNI_STORAGE_KIND:-etcd}"
OMNI_STORAGE_SQLITE_PATH="${OMNI_STORAGE_SQLITE_PATH:-/_out/secondary-storage/omni.sqlite}"
OMNI_ETCD_EMBEDDED="${OMNI_ETCD_EMBEDDED:-true}"
OMNI_ETCD_EMBEDDED_DB_PATH="${OMNI_ETCD_EMBEDDED_DB_PATH:-/_out/etcd}"
OMNI_EXTRA_ARGS_DEFAULT="--storage-kind=${OMNI_STORAGE_KIND} --sqlite-storage-path=${OMNI_STORAGE_SQLITE_PATH}"
if [ "$OMNI_STORAGE_KIND" = "etcd" ] && [ "$OMNI_ETCD_EMBEDDED" = "true" ]; then
  OMNI_EXTRA_ARGS_DEFAULT="${OMNI_EXTRA_ARGS_DEFAULT} --etcd-embedded --etcd-embedded-db-path=${OMNI_ETCD_EMBEDDED_DB_PATH}"
fi
if [ -n "${OMNI_IMAGE_FACTORY_ADDRESS:-}" ]; then
  OMNI_EXTRA_ARGS_DEFAULT="${OMNI_EXTRA_ARGS_DEFAULT} --image-factory-address=${OMNI_IMAGE_FACTORY_ADDRESS}"
fi
if [ "${OMNI_ENABLE_BREAK_GLASS_CONFIGS:-false}" = "true" ]; then
  OMNI_EXTRA_ARGS_DEFAULT="${OMNI_EXTRA_ARGS_DEFAULT} --enable-break-glass-configs"
fi
# Auto-accept the EULA on start so an Omni upgrade never needs a manual
# browser click before omnictl/cluster provisioning can proceed again.
if [ -n "${OMNI_EULA_ACCEPT_EMAIL:-}" ]; then
  OMNI_EXTRA_ARGS_DEFAULT="${OMNI_EXTRA_ARGS_DEFAULT} --eula-accept-email=${OMNI_EULA_ACCEPT_EMAIL} --eula-accept-name=${OMNI_EULA_ACCEPT_NAME:-${OMNI_EULA_ACCEPT_EMAIL}}"
fi
OMNI_EXTRA_ARGS="${OMNI_EXTRA_ARGS:-$OMNI_EXTRA_ARGS_DEFAULT}"
CADDY_TS_DOMAIN="${OMNI_TS_DOMAIN:-${OMNI_DOMAIN}}"
# Only set public domain if explicitly configured — avoids generating a Caddy block with no cert
CADDY_PUBLIC_DOMAIN="${OMNI_PUBLIC_DOMAIN:-}"
# Caddy runs in a container; public certs are mounted at /opt/certs (not the host path).
# Caddy obtains *.ts.net certs from host tailscaled via the mounted tailscaled socket.
CADDY_CERTS_MOUNT="/opt/certs"
CADDY_TS_CERT_PATH="${OMNI_TS_CERT_PATH:-${CADDY_CERTS_MOUNT}/tailscale.crt}"
CADDY_TS_KEY_PATH="${OMNI_TS_KEY_PATH:-${CADDY_CERTS_MOUNT}/tailscale.key}"
CADDY_MACHINE_API_CERT_PATH="${OMNI_MACHINE_API_CERT_PATH:-${CADDY_CERTS_MOUNT}/machine-api.crt}"
CADDY_MACHINE_API_KEY_PATH="${OMNI_MACHINE_API_KEY_PATH:-${CADDY_CERTS_MOUNT}/machine-api.key}"
CADDY_PUBLIC_CERT_PATH="${OMNI_PUBLIC_CERT_PATH:-${CADDY_CERTS_MOUNT}/public.crt}"
CADDY_PUBLIC_KEY_PATH="${OMNI_PUBLIC_KEY_PATH:-${CADDY_CERTS_MOUNT}/public.key}"

AUTH_COMBINED="${AUTH} ${OMNI_EXTRA_ARGS}"
OMNI_SERVER_CERT_FILE="${OMNI_TLS_CERT_FILE:-${CERT_FILE}}"
OMNI_SERVER_KEY_FILE="${OMNI_TLS_KEY_FILE:-${KEY_FILE}}"

cat > "$OUT_ENV" <<EOV
OMNI_IMG_TAG=${OMNI_IMG_TAG}
OMNI_ACCOUNT_UUID=${OMNI_ACCOUNT_UUID}
NAME=${NAME}
EVENT_SINK_PORT=${EVENT_SINK_PORT}
TLS_CERT=${OMNI_SERVER_CERT_FILE}
TLS_KEY=${OMNI_SERVER_KEY_FILE}
ETCD_VOLUME_PATH=${ETCD_DIR}
# upstream compose.yaml uses SQLITE_STORAGE_PATH for the secondary volume
# mount; the caddy override still references SECONDARY_STORAGE_PATH. Emit both.
SQLITE_STORAGE_PATH=${SECONDARY_STORAGE_DIR}
SECONDARY_STORAGE_PATH=${SECONDARY_STORAGE_DIR}
ETCD_ENCRYPTION_KEY=${ENC_KEY}
BIND_ADDR=${BIND_ADDR}
MACHINE_API_BIND_ADDR=${MACHINE_API_BIND_ADDR}
K8S_PROXY_BIND_ADDR=${K8S_PROXY_BIND_ADDR}
ADVERTISED_API_URL=${ADVERTISED_API_URL}
ADVERTISED_K8S_PROXY_URL=${ADVERTISED_K8S_PROXY_URL}
SIDEROLINK_ADVERTISED_API_URL=${SIDEROLINK_ADVERTISED_API_URL}
SIDEROLINK_WIREGUARD_ADVERTISED_ADDR=${SIDEROLINK_WIREGUARD_ADVERTISED_ADDR}
INITIAL_USER_EMAILS=${INITIAL_USER_EMAILS}
TLS_MODE=${TLS_MODE}
CADDY_TS_DOMAIN=${CADDY_TS_DOMAIN}
CADDY_PUBLIC_DOMAIN=${CADDY_PUBLIC_DOMAIN}
CADDY_TS_CERT_PATH=${CADDY_TS_CERT_PATH}
CADDY_TS_KEY_PATH=${CADDY_TS_KEY_PATH}
CADDY_MACHINE_API_CERT_PATH=${CADDY_MACHINE_API_CERT_PATH}
CADDY_MACHINE_API_KEY_PATH=${CADDY_MACHINE_API_KEY_PATH}
CADDY_PUBLIC_CERT_PATH=${CADDY_PUBLIC_CERT_PATH}
CADDY_PUBLIC_KEY_PATH=${CADDY_PUBLIC_KEY_PATH}
EOV

# AUTH may contain spaces and special chars — write it quoted so `source compose.env` is safe
printf "AUTH='%s'\n" "${AUTH_COMBINED}" >> "$OUT_ENV"

echo "Wrote ${OUT_ENV}"
