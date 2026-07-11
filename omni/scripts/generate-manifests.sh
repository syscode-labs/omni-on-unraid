#!/usr/bin/env bash
# Generate inline manifest content for omni/patches/inline-manifests.yaml.
set -euo pipefail

CILIUM_VERSION="${CILIUM_VERSION:-1.17.2}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.14.4}"
ARGOCD_APP_REPO_URL="${ARGOCD_APP_REPO_URL:-https://github.com/syscode-labs/oci-talos-gitops-apps}"
ARGOCD_APP_PATH="${ARGOCD_APP_PATH:-bootstrap}"
ARGOCD_APP_TARGET_REVISION="${ARGOCD_APP_TARGET_REVISION:-HEAD}"

# Argo topology selector.
#   hub        : omit in-cluster Argo — a central hub Argo (on the Omni VM k8s) manages
#                this cluster as a spoke (default for this homelab).
#   in-cluster : bootstrap Argo CD + root App-of-Apps inside this cluster.
#   Cilium is always in-cluster (it is the CNI).
ARGO_MODE="${ARGO_MODE:-hub}"
case "$ARGO_MODE" in
  in-cluster|hub) ;;
  *) echo "ARGO_MODE must be 'in-cluster' or 'hub', got '${ARGO_MODE}'" >&2; exit 1 ;;
esac

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

if [ "$ARGO_MODE" = "in-cluster" ]; then
  curl -sL "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" \
    > "${TMPDIR}/argocd.yaml"
  ARGOCD_CONTENT="$(sed 's/^/        /' "${TMPDIR}/argocd.yaml")"
fi

CILIUM_CONTENT="$(sed 's/^/        /' "${TMPDIR}/cilium.yaml")"

cat > "${PATCH_FILE}" <<EOF
# Talos inline manifests applied during cluster bootstrap by the first control plane.
#
# Regenerate after Cilium or Argo CD version bumps:
#   mise run omni:talos:generate-manifests                         # central hub Argo (default)
#   ARGO_MODE=in-cluster mise run omni:talos:generate-manifests    # in-cluster Argo + App-of-Apps
#
# ARGO_MODE: ${ARGO_MODE}
# Cilium: ${CILIUM_VERSION}; kubeProxyReplacement=true; KubePrism localhost:7445

cluster:
  inlineManifests:
    - name: cilium
      contents: |
        # cilium ${CILIUM_VERSION}; generated $(date -u +%Y-%m-%d)
${CILIUM_CONTENT}
EOF

if [ "$ARGO_MODE" = "in-cluster" ]; then
cat >> "${PATCH_FILE}" <<EOF

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
else
cat >> "${PATCH_FILE}" <<'EOF'

    # ARGO_MODE=hub — no in-cluster Argo. A central hub Argo (on the Omni VM k8s) manages
    # this cluster as a spoke. This block ships the ServiceAccount the hub authenticates as,
    # so the token exists from first boot. Registration (read token → sops → commit) is the
    # single manual step, documented once in:
    #   syscode-ai-internal-plans/projects/imp/docs/plans/2026-07-11-argo-hub-spoke-registration-runbook.md
    - name: argocd-manager
      contents: |
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: argocd-manager
          namespace: kube-system
        ---
        apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRoleBinding
        metadata:
          name: argocd-manager
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: ClusterRole
          name: cluster-admin
        subjects:
          - kind: ServiceAccount
            name: argocd-manager
            namespace: kube-system
        ---
        # Non-expiring legacy SA token (auto-token Secrets removed in k8s 1.24). Deliberate:
        # a bound short-lived token can't be pre-committed for GitOps registration.
        apiVersion: v1
        kind: Secret
        metadata:
          name: argocd-manager-token
          namespace: kube-system
          annotations:
            kubernetes.io/service-account.name: argocd-manager
        type: kubernetes.io/service-account-token
EOF
fi

echo "Wrote ${PATCH_FILE} (ARGO_MODE=${ARGO_MODE})"
