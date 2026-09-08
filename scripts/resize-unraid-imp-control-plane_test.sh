#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/resize-unraid-imp-control-plane.sh"
bash -n "$script"
cd "$root"
grep -Fq 'target_domain="unraid-lab-control-planes-6rrw7n"' "$script"
grep -Fq 'target_memory_mib=7168' "$script"
grep -Fq 'memory: 4096' "$root/omni/machine-classes/control-plane.yaml"
grep -Fq 'omni.sidero.dev/machine: ${target_id}' "$script"
grep -Fq 'kind: KubeNodeConfig' "$script"
grep -Fq 'remote-operations supervisor' "$script"
grep -Fq 'RUNNING Ready (3/3)' "$script"
grep -Fq 'kubectl drain' "$script"
grep -Fq 'virsh setmaxmem' "$script"
grep -Fq 'virsh setmem' "$script"
grep -Fq 'imp/enabled-' "$script"
grep -Fq 'imp.dev/runner=true:NoSchedule' "$script"
printf 'resize-unraid-imp-control-plane static checks passed\n'
