#!/bin/bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/iptables" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$IPTABLES_LOG"
exit 0
EOF
chmod +x "$tmp_dir/iptables"

export IPTABLES_LOG="$tmp_dir/iptables.log"
PATH="$tmp_dir:$PATH" bash "$root_dir/contrib/libvirt-network-hook" default started

grep -F -- '-s 192.168.122.0/24 -d 100.72.134.50 -j RETURN' "$IPTABLES_LOG" >/dev/null
grep -F -- '-s 192.168.122.0/24 -d 100.80.125.127 -j RETURN' "$IPTABLES_LOG" >/dev/null
