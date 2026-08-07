#!/usr/bin/env bash
# Generate the Talos inline-manifests patch consumed by the renderer's base
# patch set, omni/patches/inline-manifests.yaml. Generic clusters — Cilium CNI.
#
# The former management-cluster branch (inline-manifests-management.yaml, Cilium
# + Argo CD + root App-of-Apps) is gone: its only consumer, the deleted
# homelab-management.yaml cluster template, no longer exists. See
# automate-talos-upgrade-pipeline task 3.5.
set -euo pipefail

CILIUM_VERSION="${CILIUM_VERSION:-1.19.6}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERIC_PATCH_FILE="${SCRIPT_DIR}/../patches/inline-manifests.yaml"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

helm repo add cilium https://helm.cilium.io/ --force-update >/dev/null
helm repo update cilium >/dev/null

helm template cilium cilium/cilium \
  --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=localhost \
  --set k8sServicePort=7445 \
  --set ipam.mode=kubernetes \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
  > "${TMPDIR}/cilium.yaml"

CILIUM_CONTENT="$(sed 's/^/        /' "${TMPDIR}/cilium.yaml")"

# --- generic patch: Cilium CNI only ---
cat > "${GENERIC_PATCH_FILE}" <<EOF
# Talos inline manifests for GENERIC clusters — Cilium CNI only.
#
# Regenerate after a Cilium version bump:
#   mise run omni:talos:generate-manifests
#
# Cilium: ${CILIUM_VERSION}; kubeProxyReplacement=true; KubePrism localhost:7445

cluster:
  inlineManifests:
    - name: cilium
      contents: |
        # cilium ${CILIUM_VERSION}; generated $(date -u +%Y-%m-%d)
${CILIUM_CONTENT}
EOF

echo "Wrote ${GENERIC_PATCH_FILE}"
