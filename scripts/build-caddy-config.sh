#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/generated/compose.env"
OUT_DIR="${ROOT_DIR}/generated/caddy"
OUT_FILE="${OUT_DIR}/Caddyfile"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing ${ENV_FILE}; run ./scripts/build-compose-env.sh first" >&2
  exit 1
fi

get_var() {
  local key="$1"
  local line
  line="$(grep -E "^${key}=" "$ENV_FILE" | head -n1 || true)"
  echo "${line#*=}"
}

TLS_MODE="$(get_var TLS_MODE)"
CADDY_TS_DOMAIN="$(get_var CADDY_TS_DOMAIN)"
CADDY_PUBLIC_DOMAIN="$(get_var CADDY_PUBLIC_DOMAIN)"
CADDY_PUBLIC_CERT_PATH="$(get_var CADDY_PUBLIC_CERT_PATH)"
CADDY_PUBLIC_KEY_PATH="$(get_var CADDY_PUBLIC_KEY_PATH)"

mkdir -p "$OUT_DIR"

if [ "${TLS_MODE:-direct}" != "caddy-sni" ]; then
  # Caddy config not needed outside SNI termination mode.
  rm -f "$OUT_FILE"
  exit 0
fi

PUBLIC_BLOCK=""
if [ -n "$CADDY_PUBLIC_DOMAIN" ] && [ -n "$CADDY_PUBLIC_CERT_PATH" ] && [ -n "$CADDY_PUBLIC_KEY_PATH" ]; then
  PUBLIC_BLOCK="
${CADDY_PUBLIC_DOMAIN} {
  tls ${CADDY_PUBLIC_CERT_PATH} ${CADDY_PUBLIC_KEY_PATH}
  reverse_proxy https://127.0.0.1:8443 {
    transport http {
      tls_insecure_skip_verify
    }
  }
}"
fi

cat >"$OUT_FILE" <<EOC
{
  admin off
}

${CADDY_TS_DOMAIN} {
  reverse_proxy https://127.0.0.1:8443 {
    transport http {
      tls_insecure_skip_verify
    }
  }
}
${PUBLIC_BLOCK}
EOC

echo "Wrote ${OUT_FILE}"
