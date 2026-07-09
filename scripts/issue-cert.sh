#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
fi

if [ -z "${OMNI_DOMAIN:-}" ]; then
  echo "Set OMNI_DOMAIN in .env" >&2
  exit 1
fi

if [ -z "${OMNI_TLS_ACME_EMAIL:-}" ]; then
  echo "Set OMNI_TLS_ACME_EMAIL in .env" >&2
  exit 1
fi

if [ -z "${OMNI_TLS_ACME_DNS_PROVIDER:-}" ]; then
  echo "Set OMNI_TLS_ACME_DNS_PROVIDER in .env (lego DNS provider name)" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env (copy templates/omni.env.example .env)" >&2
  exit 1
fi

TLS_CACHE_DIR="${OMNI_TLS_CERT_LOCAL_DIR:-${ROOT_DIR}/.cache/tls}"
RENEW_BEFORE_DAYS="${OMNI_TLS_RENEW_BEFORE_DAYS:-30}"
CERT_FILE="${TLS_CACHE_DIR}/certificates/${OMNI_DOMAIN}.crt"
KEY_FILE="${TLS_CACHE_DIR}/certificates/${OMNI_DOMAIN}.key"
SECONDS_LEFT=$((RENEW_BEFORE_DAYS * 24 * 60 * 60))

mkdir -p "$TLS_CACHE_DIR"

domains=( -d "$OMNI_DOMAIN" )
if [ -n "${OMNI_TLS_ACME_SANS:-}" ]; then
  IFS=',' read -r -a sans <<< "$OMNI_TLS_ACME_SANS"
  for san in "${sans[@]}"; do
    san="$(echo "$san" | tr -d '[:space:]')"
    if [ -n "$san" ]; then
      domains+=( -d "$san" )
    fi
  done
fi

if [ -f "$CERT_FILE" ] && openssl x509 -in "$CERT_FILE" -checkend "$SECONDS_LEFT" >/dev/null 2>&1; then
  echo "Existing certificate is still valid for more than ${RENEW_BEFORE_DAYS} days: $CERT_FILE"
  echo "TLS cert: $CERT_FILE"
  echo "TLS key : $KEY_FILE"
  exit 0
fi

cmd=(
  docker run --rm
  -v "${TLS_CACHE_DIR}:/lego"
  --env-file "$ENV_FILE"
  goacme/lego:latest
  --accept-tos
  --path /lego
  --email "$OMNI_TLS_ACME_EMAIL"
  --dns "$OMNI_TLS_ACME_DNS_PROVIDER"
  "${domains[@]}"
)

if [ -f "$CERT_FILE" ]; then
  "${cmd[@]}" renew --days "$RENEW_BEFORE_DAYS"
else
  "${cmd[@]}" run
fi

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  echo "Certificate issuance/renewal finished but cert/key files were not found." >&2
  echo "Expected: $CERT_FILE and $KEY_FILE" >&2
  exit 1
fi

echo "TLS cert: $CERT_FILE"
echo "TLS key : $KEY_FILE"
