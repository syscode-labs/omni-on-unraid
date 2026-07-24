#!/usr/bin/env bash
# Generate Talos inline manifests for the Omni cluster patches.
#
# Emits two files:
#   omni/patches/inline-manifests.yaml             generic clusters — Cilium CNI only
#   omni/patches/inline-manifests-management.yaml  mgmt cluster — Cilium + Argo CD + root App
set -euo pipefail

CILIUM_VERSION="${CILIUM_VERSION:-1.17.2}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.14.4}"
ARGOCD_APP_REPO_URL="${ARGOCD_APP_REPO_URL:-https://github.com/syscode-labs/oci-talos-gitops-apps}"
ARGOCD_APP_PATH="${ARGOCD_APP_PATH:-bootstrap}"
ARGOCD_APP_TARGET_REVISION="${ARGOCD_APP_TARGET_REVISION:-HEAD}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERIC_PATCH_FILE="${SCRIPT_DIR}/../patches/inline-manifests.yaml"
MGMT_PATCH_FILE="${SCRIPT_DIR}/../patches/inline-manifests-management.yaml"
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

# Upstream install.yaml carries NO namespace on its resources — it relies on
# `kubectl apply -n argocd`. Talos applies inline manifests verbatim with no
# namespace default, so the namespaced resources land in `default` and Argo's
# runtime never comes up in argocd. Stamp with kustomize (also fixes the RBAC
# binding subjects) and prepend the Namespace since kustomize won't create it.
mkdir -p "${TMPDIR}/argocd"
curl -sfL "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" \
  -o "${TMPDIR}/argocd/install.yaml"
cat > "${TMPDIR}/argocd/kustomization.yaml" <<'KUST'
namespace: argocd
resources:
  - install.yaml
KUST
{ printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: argocd\n---\n'; \
  kubectl kustomize "${TMPDIR}/argocd"; } > "${TMPDIR}/argocd.yaml"

CILIUM_CONTENT="$(sed 's/^/        /' "${TMPDIR}/cilium.yaml")"
ARGOCD_CONTENT="$(sed 's/^/        /' "${TMPDIR}/argocd.yaml")"

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

# --- mgmt patch: Cilium + Argo CD + root App-of-Apps ---
cat > "${MGMT_PATCH_FILE}" <<EOF
# Talos inline manifests for the homelab-management (mgmt) cluster.
# Cilium CNI + Argo CD + root App-of-Apps (GitOps).
#
# Regenerate after a Cilium or Argo CD version bump:
#   mise run omni:talos:generate-manifests
#
# Cilium: ${CILIUM_VERSION}; kubeProxyReplacement=true; KubePrism localhost:7445
# Argo CD: ${ARGOCD_VERSION}; raw install manifest plus root App-of-Apps -> ${ARGOCD_APP_REPO_URL}

cluster:
  inlineManifests:
    - name: cilium
      contents: |
        # cilium ${CILIUM_VERSION}; generated $(date -u +%Y-%m-%d)
${CILIUM_CONTENT}

    - name: argocd
      contents: |
        # argocd ${ARGOCD_VERSION}; generated $(date -u +%Y-%m-%d)
${ARGOCD_CONTENT}

    - name: argocd-app-of-apps
      contents: |
        apiVersion: argoproj.io/v1alpha1
        kind: Application
        metadata:
          name: root
          namespace: argocd
        spec:
          project: default
          source:
            repoURL: ${ARGOCD_APP_REPO_URL}
            targetRevision: ${ARGOCD_APP_TARGET_REVISION}
            path: ${ARGOCD_APP_PATH}
          destination:
            server: https://kubernetes.default.svc
            namespace: argocd
          syncPolicy:
            automated:
              prune: true
              selfHeal: true
EOF

echo "Wrote ${GENERIC_PATCH_FILE}"
echo "Wrote ${MGMT_PATCH_FILE}"
