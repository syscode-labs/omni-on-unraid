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
CADDY_TS_BIND_ADDR="$(get_var CADDY_TS_BIND_ADDR)"
MACHINE_API_BIND_ADDR="$(get_var MACHINE_API_BIND_ADDR)"
K8S_PROXY_BIND_ADDR="$(get_var K8S_PROXY_BIND_ADDR)"

mkdir -p "$OUT_DIR"

if [ "${TLS_MODE:-direct}" != "caddy-sni" ]; then
  # Caddy config not needed outside SNI termination mode.
  rm -f "$OUT_FILE"
  exit 0
fi

if [ -z "$CADDY_TS_BIND_ADDR" ]; then
  echo "Set OMNI_TS_IP when OMNI_TLS_MODE=caddy-sni so Caddy can bind the Kubernetes proxy without conflicting with Omni's loopback listener." >&2
  exit 1
fi

cat >"$OUT_FILE" <<EOC
{
  admin off
  default_sni ${CADDY_TS_DOMAIN}
  fallback_sni ${CADDY_TS_DOMAIN}
}

${CADDY_TS_DOMAIN} {
  tls {
    get_certificate tailscale
  }
  reverse_proxy https://127.0.0.1:8443 {
    transport http {
      tls_insecure_skip_verify
    }
  }
}

${CADDY_TS_DOMAIN}:8090 {
  tls {
    get_certificate tailscale
  }
  reverse_proxy https://${MACHINE_API_BIND_ADDR} {
    transport http {
      tls_insecure_skip_verify
    }
  }
}

${CADDY_TS_DOMAIN}:8100 {
  bind ${CADDY_TS_BIND_ADDR}
  tls {
    get_certificate tailscale
  }
  reverse_proxy https://${K8S_PROXY_BIND_ADDR} {
    transport http {
      tls_insecure_skip_verify
    }
  }
}
EOC

echo "Wrote ${OUT_FILE}"
