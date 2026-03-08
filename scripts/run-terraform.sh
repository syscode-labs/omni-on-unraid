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

if [ -z "${OMNI_LIBVIRT_URI:-}" ] && [ -n "${OMNI_LIBVIRT_IMAGE_SSH_TARGET:-}" ]; then
  libvirt_host="${OMNI_LIBVIRT_IMAGE_SSH_TARGET#*@}"
  OMNI_LIBVIRT_URI="qemu+tcp://${libvirt_host}/system"
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

if [ -z "${TF_VAR_base_image_path:-}" ]; then
  candidate="${OMNI_BASE_IMAGE_PATH:-}"
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    export TF_VAR_base_image_path="$candidate"
  else
    local_base_image_path="${OMNI_LOCAL_BASE_IMAGE_PATH:-${ROOT_DIR}/.cache/images/ubuntu-noble-cloudimg-amd64.qcow2}"
    if [ ! -f "$local_base_image_path" ]; then
      base_url="${OMNI_BASE_IMAGE_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}"
      mkdir -p "$(dirname "$local_base_image_path")"
      curl -fL "$base_url" -o "$local_base_image_path"
    fi
    export TF_VAR_base_image_path="$local_base_image_path"
  fi
fi

if [ -z "${TF_VAR_tailscale_authkey:-}" ] && [ -n "${OMNI_TAILSCALE_AUTHKEY:-}" ]; then
  export TF_VAR_tailscale_authkey="$OMNI_TAILSCALE_AUTHKEY"
fi

if [ -z "${TF_VAR_tailscale_hostname:-}" ] && [ -n "${OMNI_TAILSCALE_HOSTNAME:-}" ]; then
  export TF_VAR_tailscale_hostname="$OMNI_TAILSCALE_HOSTNAME"
fi

if [ -z "${TF_VAR_network_bridge:-}" ]; then
  if [ -n "${OMNI_LIBVIRT_BRIDGE:-}" ]; then
    export TF_VAR_network_bridge="$OMNI_LIBVIRT_BRIDGE"
  elif [ -n "${OMNI_LIBVIRT_NETWORK:-}" ]; then
    export TF_VAR_network_bridge="$OMNI_LIBVIRT_NETWORK"
  fi
fi

if [ -z "${TF_VAR_vm_mac:-}" ]; then
  if [ -n "${OMNI_VM_MAC:-}" ]; then
    export TF_VAR_vm_mac="$OMNI_VM_MAC"
  else
    vm_name="${OMNI_VM_NAME:-omni-vm}"
    if [ -n "${OMNI_LIBVIRT_URI:-}" ] && command -v virsh >/dev/null 2>&1; then
      current_mac="$(virsh -c "$OMNI_LIBVIRT_URI" domiflist "$vm_name" 2>/dev/null | awk '/network|bridge/ {print $5; exit}')"
      if [ -n "$current_mac" ]; then
        export TF_VAR_vm_mac="$current_mac"
      fi
    fi
  fi
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
    tf_apply_args=()
    if [ "${TF_AUTO_APPROVE:-1}" = "1" ]; then
      tf_apply_args+=("-auto-approve")
    fi
    if [ "${TF_REPLACE_DOMAIN:-0}" = "1" ]; then
      tf_apply_args+=("-replace=libvirt_domain.vm")
    fi
    terraform apply "${tf_apply_args[@]}"
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
