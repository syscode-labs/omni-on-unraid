#!/usr/bin/env bash
# Generate inline manifest content for omni/patches/inline-manifests.yaml.
set -euo pipefail

CILIUM_VERSION="${CILIUM_VERSION:-1.17.2}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.14.4}"
ARGOCD_APP_REPO_URL="${ARGOCD_APP_REPO_URL:-https://github.com/syscode-labs/oci-talos-gitops-apps}"
ARGOCD_APP_PATH="${ARGOCD_APP_PATH:-bootstrap}"
ARGOCD_APP_TARGET_REVISION="${ARGOCD_APP_TARGET_REVISION:-HEAD}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="${SCRIPT_DIR}/../patches/inline-manifests.yaml"
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
  > "${TMPDIR}/cilium.yaml"

curl -sL "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" \
  > "${TMPDIR}/argocd.yaml"

CILIUM_CONTENT="$(sed 's/^/        /' "${TMPDIR}/cilium.yaml")"
ARGOCD_CONTENT="$(sed 's/^/        /' "${TMPDIR}/argocd.yaml")"

cat > "${PATCH_FILE}" <<EOF
# Talos inline manifests applied during cluster bootstrap by the first control plane.
#
# Regenerate after Cilium or Argo CD version bumps:
#   mise run omni:talos:generate-manifests
#
# Cilium: ${CILIUM_VERSION}; kubeProxyReplacement=true; KubePrism localhost:7445
# Argo CD: ${ARGOCD_VERSION}; raw install manifest plus root App-of-Apps

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

echo "Wrote ${PATCH_FILE}"
