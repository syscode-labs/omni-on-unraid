#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
env_file="${SECRETS_ENV:-$repo_root/omni/secrets.env}"

[ -f "$env_file" ] || { echo "missing $env_file" >&2; exit 1; }
set -a
. "$env_file"
set +a

: "${TS_OAUTH_CLIENT_ID:?set in $env_file}"
: "${TS_OAUTH_CLIENT_SECRET:?set in $env_file}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/secret.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: tailscale
---
apiVersion: v1
kind: Secret
metadata:
  name: operator-oauth
  namespace: tailscale
type: Opaque
stringData:
  client_id: "$TS_OAUTH_CLIENT_ID"
  client_secret: "$TS_OAUTH_CLIENT_SECRET"
EOF

printf 'cluster:\n  inlineManifests: []\n' > "$tmp/patch.yaml"
MF="$tmp/secret.yaml" yq -i '.cluster.inlineManifests += [{"name":"bootstrap-tailscale-oauth","contents":loadstr(strenv(MF))}]' "$tmp/patch.yaml"

cat > "$tmp/configpatch.yaml" <<'EOF'
metadata:
  namespace: default
  type: ConfigPatches.omni.sidero.dev
  id: 500-cluster-unraid-lab-bootstrap-tailscale-oauth
  labels:
    omni.sidero.dev/cluster: unraid-lab
spec:
  data: ""
EOF

PATCH="$tmp/patch.yaml" yq -i '.spec.data = loadstr(strenv(PATCH)) | .spec.data style="literal"' "$tmp/configpatch.yaml"
omnictl apply -f "$tmp/configpatch.yaml"
