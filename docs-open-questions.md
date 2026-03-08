# Open Questions (Need Interactive Brainstorm)

1. TLS strategy for Omni on Unraid
- Use reverse proxy (NPM/Traefik/Caddy) with external TLS termination?
- Or mount native cert/key directly into Omni compose stack?

2. Secrets handling
- Where to store `OMNI_ACCOUNT_UUID`, keys, and cert paths declaratively?
- Preferred tool: SOPS+age, Vault, or local sealed env file?

3. Host networking model
- Keep Omni `network_mode: host` (upstream default) or front with reverse proxy and strict port mapping?

4. Backup target
- Local Unraid share only, or replicated off-host backup path?
