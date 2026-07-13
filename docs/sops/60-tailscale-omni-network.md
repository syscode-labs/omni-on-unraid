# Tailscale Omni Network

Use Tailscale for Talos-to-Omni join traffic.

- SideroLink API URL: `https://omni.example.ts.net:8090/`
- SideroLink WireGuard address: `100.64.0.10:50180`
- Omni node tag: `tag:omni`
- Talos node auth key variable: `NODES_TAILSCALE_AUTHKEY`
- Talos node source tag: `tag:talos`

Do not use LAN IPs for Talos join paths. The API endpoint can use MagicDNS.
The WireGuard advertised address must be `ip:port`, so use the Omni Tailscale
IP rather than the LAN IP.

## Tailnet Policy

Current netmap evidence showed access to `tag:omni` on TCP `443`/`8443`, but not
TCP `8090` or UDP `50180`. Add policy like this. The Talos auth key used by
`NODES_TAILSCALE_AUTHKEY` must be reusable and pre-tagged as `tag:talos`.

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:workstations", "tag:client"],
      "proto": "tcp",
      "dst": ["tag:omni:443,8090"]
    },
    {
      "action": "accept",
      "src": ["tag:talos"],
      "proto": "tcp",
      "dst": ["tag:omni:8090"]
    },
    {
      "action": "accept",
      "src": ["tag:talos"],
      "proto": "udp",
      "dst": ["tag:omni:50180"]
    }
  ]
}
```

If the tailnet policy uses grants instead of ACLs, keep the same intent:
operator workstations need TCP `8090`; Talos nodes need TCP `8090` and UDP
`50180` to `tag:omni`.
