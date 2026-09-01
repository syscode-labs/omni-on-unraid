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

validate_version() {
  local label="$1"
  local version="$2"
  if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
    echo "resolve-cluster-versions: invalid ${label} version '${version}'" >&2
    exit 1
  fi
}

versions_yaml="$(curl -fsSL "$versions_url")"

global_talos="$(printf '%s' "$versions_yaml" | yq eval '.talos // ""' -)"
cluster_talos="$(printf '%s' "$versions_yaml" | yq eval ".clusters.${cluster_name}.talos // \"\"" -)"
cluster_k8s="$(printf '%s' "$versions_yaml" | yq eval ".clusters.${cluster_name}.kubernetes // \"\"" -)"

talos_version="${cluster_talos:-$global_talos}"

if [ -z "$talos_version" ] || [ "$talos_version" = "null" ]; then
  echo "resolve-cluster-versions: no talos version resolved for cluster '${cluster_name}'" >&2
  exit 1
fi

# Kubernetes is never inherited across a diverging Talos target: the global
# kubernetes pin belongs to the global Talos minor, so carrying it onto a
# cluster pinned to a different Talos is the drift this file exists to stop.
# Matches scripts/check-version-drift.py in syscode-homelab-gitops-apps.
if [ -n "$cluster_k8s" ] && [ "$cluster_k8s" != "null" ]; then
  kubernetes_version="$cluster_k8s"
elif [ -n "$cluster_talos" ] && [ "$cluster_talos" != "$global_talos" ]; then
  echo "resolve-cluster-versions: cluster '${cluster_name}' pins talos ${cluster_talos}" >&2
  echo "  but the global pin is ${global_talos} and no kubernetes override is set." >&2
  echo "  Derive the Kubernetes version for ${cluster_talos} and pin it explicitly" >&2
  echo "  under clusters.${cluster_name}.kubernetes in versions.yaml." >&2
  exit 1
else
  kubernetes_version="$(printf '%s' "$versions_yaml" | yq eval '.kubernetes // ""' -)"
fi
if [ -z "$kubernetes_version" ] || [ "$kubernetes_version" = "null" ]; then
  echo "resolve-cluster-versions: no kubernetes version resolved for cluster '${cluster_name}'" >&2
  exit 1
fi

validate_version "talos" "$talos_version"
validate_version "kubernetes" "$kubernetes_version"

echo "TALOS_VERSION=${talos_version}"
echo "KUBERNETES_VERSION=${kubernetes_version}"
