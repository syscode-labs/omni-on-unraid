#!/usr/bin/env bash
set -euo pipefail

# Resolves the pinned Talos/Kubernetes versions for one cluster from the
# hand-owned versions.yaml in syscode-homelab-gitops-apps. Prints
# TALOS_VERSION=... and KUBERNETES_VERSION=... shell assignments; callers
# `eval` the output to load them.
#
# A cluster entry may override `talos` and/or `kubernetes`; unset fields
# inherit the global pin. See versions.yaml for the authoritative shape.

cluster_name="${1:-${CLUSTER_NAME:-unraid-lab}}"
versions_url="${VERSIONS_YAML_URL:-https://raw.githubusercontent.com/syscode-labs/syscode-homelab-gitops-apps/main/omni/versions.yaml}"

versions_yaml="$(curl -fsSL "$versions_url")"

talos_version="$(printf '%s' "$versions_yaml" | yq eval ".clusters.${cluster_name}.talos // .talos" -)"
kubernetes_version="$(printf '%s' "$versions_yaml" | yq eval ".clusters.${cluster_name}.kubernetes // .kubernetes" -)"

if [ -z "$talos_version" ] || [ "$talos_version" = "null" ]; then
  echo "resolve-cluster-versions: no talos version resolved for cluster '${cluster_name}'" >&2
  exit 1
fi
if [ -z "$kubernetes_version" ] || [ "$kubernetes_version" = "null" ]; then
  echo "resolve-cluster-versions: no kubernetes version resolved for cluster '${cluster_name}'" >&2
  exit 1
fi

echo "TALOS_VERSION=${talos_version}"
echo "KUBERNETES_VERSION=${kubernetes_version}"
