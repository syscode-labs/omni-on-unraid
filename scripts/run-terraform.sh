#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <init|plan|apply|destroy>" >&2
  exit 1
fi

action="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
TF_DIR="${ROOT_DIR}/terraform/libvirt"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
fi

if [ -z "${TF_VAR_libvirt_uri:-}" ] && [ -n "${OMNI_LIBVIRT_URI:-}" ]; then
  export TF_VAR_libvirt_uri="$OMNI_LIBVIRT_URI"
fi

if [ -z "${TF_VAR_ssh_public_key:-}" ]; then
  key_path="${OMNI_SSH_PUBLIC_KEY_PATH:-}"
  if [ -z "$key_path" ]; then
    echo "Set OMNI_SSH_PUBLIC_KEY_PATH in .env or TF_VAR_ssh_public_key in environment" >&2
    exit 1
  fi
  if [ ! -f "$key_path" ]; then
    echo "SSH public key file not found: $key_path" >&2
    exit 1
  fi
  export TF_VAR_ssh_public_key
  TF_VAR_ssh_public_key="$(tr -d '\r\n' < "$key_path")"
fi

if [ -z "${TF_VAR_base_image_path:-}" ] && [ -n "${OMNI_BASE_IMAGE_PATH:-}" ]; then
  export TF_VAR_base_image_path="$OMNI_BASE_IMAGE_PATH"
fi

if [ -z "${TF_VAR_tailscale_authkey:-}" ] && [ -n "${OMNI_TAILSCALE_AUTHKEY:-}" ]; then
  export TF_VAR_tailscale_authkey="$OMNI_TAILSCALE_AUTHKEY"
fi

if [ -z "${TF_VAR_tailscale_hostname:-}" ] && [ -n "${OMNI_TAILSCALE_HOSTNAME:-}" ]; then
  export TF_VAR_tailscale_hostname="$OMNI_TAILSCALE_HOSTNAME"
fi

cd "$TF_DIR"
case "$action" in
  init)
    terraform init -upgrade
    ;;
  plan)
    terraform init -upgrade
    terraform plan
    ;;
  apply)
    terraform init -upgrade
    terraform apply
    ;;
  destroy)
    terraform init -upgrade
    terraform destroy
    ;;
  *)
    echo "Unsupported action: $action" >&2
    exit 1
    ;;
esac
