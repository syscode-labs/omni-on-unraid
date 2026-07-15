# Tailscale Omni Network — Talos-to-Omni join (routed, no node tailscale)

Talos nodes join a **tailnet-only** Omni without running Tailscale themselves.
Early tailscale-in-Talos is removed: in maintenance mode the `ext-tailscale`
service hangs `Waiting for service "cri"`, so it never connects. Instead the
libvirt host routes node traffic into the tailnet.

Full root-cause + verification: plans-repo
`projects/omni-on-unraid/artifacts/2026-07-16-libvirt-unraid-lab-tailnet-join.md`.

## Omni-side facts

- SideroLink API URL (advertised to nodes): `https://<omni-ts-dns>:8090/`
- SideroLink WireGuard address: `<omni-ts-ip>:50180`
- Omni node tag: `tag:omni`
- Omni accepts subnet routes (`tailscale ... RouteAll: true`)

Use MagicDNS for the API endpoint; the WireGuard advertised address must be
`ip:port` (Omni Tailscale IP, not a LAN IP). Nodes resolve the `*.ts.net` name
via libvirt dnsmasq → the LAN resolver that has MagicDNS — no node tailscale
needed.

## The three requirements for a node to join

1. **No early tailscale.** The libvirt provider must not inject a tailscale
   `ExtensionServiceConfig` (`NODES_TAILSCALE_AUTHKEY` unset / removed).
2. **Route + ACL.** The libvirt host advertises the VM subnet and the tailnet
   policy grants it to Omni:
   - Host: `tailscale set --advertise-routes=<vm-subnet>` (+ approve).
   - Policy (grants form):
     ```jsonc
     "autoApprovers": { "routes": { "<vm-subnet>": ["<host-tag>"] } },
     "grants": [ { "src": ["<vm-subnet>"], "dst": ["tag:omni"],
                  "ip": ["tcp:8090","udp:50180"] } ]
     ```
     Operator workstations still need `tcp:8090` to `tag:omni`.
3. **Masquerade exemption.** libvirt NATs VM egress, which rewrites the source
   to the host tailnet IP and breaks the subnet grant. Exempt Omni-bound traffic
   so the VM source IP survives:
   ```
   iptables -t nat -I LIBVIRT_PRT 1 -s <vm-subnet> -d <omni-ts-ip> -j RETURN
   ```
   Persisted via the libvirt network hook in `contrib/libvirt-network-hook`
   (installed at `/etc/libvirt/hooks/network` on the libvirt host).

## Current lab values

- VM subnet: `192.168.122.0/24` (libvirt `default` net on bookofshadows)
- Omni tailnet IP: `100.72.134.50`; host tag: `tag:homelab-servers`

## Verify

```bash
omnictl get links                 # node Link CONNECTED=true, LASTENDPOINT 192.168.122.x
# on the libvirt host:
conntrack -L | grep <omni-ts-ip>  # src=192.168.122.x preserved, [ASSURED]
```
