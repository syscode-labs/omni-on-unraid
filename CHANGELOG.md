# Changelog

## [0.2.0](https://github.com/syscode-labs/omni-on-unraid/compare/v0.1.0...v0.2.0) (2026-08-07)


### Features

* **omni:** add homelab-management Argo hub cluster; split inline manifests ([#3](https://github.com/syscode-labs/omni-on-unraid/issues/3)) ([a310998](https://github.com/syscode-labs/omni-on-unraid/commit/a31099888718be4543bf19efb0cb5dab167c8115))
* **omni:** health and compose-env verification tooling ([43c536d](https://github.com/syscode-labs/omni-on-unraid/commit/43c536dfde4bd40822b141bad83ed9d98e0a89c7))
* **omni:** node tailnet enablement in cluster render ([13f29af](https://github.com/syscode-labs/omni-on-unraid/commit/13f29af4b406bc93724feb4373b8516def0fde36))
* **omni:** on-prem Image Factory + GHCR auth; terraform base-image safety ([#6](https://github.com/syscode-labs/omni-on-unraid/issues/6)) ([8882ef2](https://github.com/syscode-labs/omni-on-unraid/commit/8882ef2f1145c48fc7a4844228bbf44bd436cfc5))
* **omni:** pin-driven render, version-gated patches, one sync path ([e8e4ebc](https://github.com/syscode-labs/omni-on-unraid/commit/e8e4ebc85d0a991b21c69d5a409cb65c5b020235))
* **omni:** tailnet-only SideroLink endpoint and Caddy SNI ([97ca065](https://github.com/syscode-labs/omni-on-unraid/commit/97ca0656ac8f56b466a12e74bed2126ffdc5953e))
* **omni:** wire install image and boot extensions for tailnet join ([947fb72](https://github.com/syscode-labs/omni-on-unraid/commit/947fb72fb05464d1145f8786ac0016b92ed4a472))
* require Tailscale OAuth before cluster apply ([e16bc60](https://github.com/syscode-labs/omni-on-unraid/commit/e16bc60f3c4c23390c30db1c14049cc5b70b2300))
* require Tailscale OAuth before cluster apply ([b0be52c](https://github.com/syscode-labs/omni-on-unraid/commit/b0be52c77f02407a5e6f8c520fad431d8a0c3416))


### Bug Fixes

* align unraid bootstrap manifests ([f1f15dc](https://github.com/syscode-labs/omni-on-unraid/commit/f1f15dc680b60744f9b1822ba290fe51667fe35a))
* align unraid bootstrap manifests ([2988def](https://github.com/syscode-labs/omni-on-unraid/commit/2988def6a2ef7716e4702f0e469879e364433728))
* libvirt Talos nodes join tailnet-only Omni (drop early tailscale) ([#5](https://github.com/syscode-labs/omni-on-unraid/issues/5)) ([84c80a9](https://github.com/syscode-labs/omni-on-unraid/commit/84c80a98ff932a7bd0fc8432cbd6700a6306e42c))
* **mise:** allow generated/ on cluster template validate/sync ([dd2f103](https://github.com/syscode-labs/omni-on-unraid/commit/dd2f1036dd82d542a28fc76e26a4291650abdef8))
* **omni:** re-pin Argo bootstrap manifests to main after PR [#17](https://github.com/syscode-labs/omni-on-unraid/issues/17) ([#8](https://github.com/syscode-labs/omni-on-unraid/issues/8)) ([c439376](https://github.com/syscode-labs/omni-on-unraid/commit/c4393766c14935fc6142ec5215767a62dd77d0fd))
* **omnirender:** narrow cluster patch set to explicit base + minor glob ([18f1c06](https://github.com/syscode-labs/omni-on-unraid/commit/18f1c060ddb0db5243919429c92b9706bd904c62))
* **render:** do not inherit kubernetes across a diverging talos pin ([b8effba](https://github.com/syscode-labs/omni-on-unraid/commit/b8effbafcfe08627c33b2ca9903e1aa62422baed))

## 0.1.0 (2026-07-09)


### Features

* add omni operator release workflow ([c77d8c5](https://github.com/syscode-labs/omni-on-unraid/commit/c77d8c591549e7486e2e7c9b64faea51c22cd46f))
* add secrets-driven github apply workflow ([ce29648](https://github.com/syscode-labs/omni-on-unraid/commit/ce2964814886ff9377b4f1d5404935ddff5af578))


### Bug Fixes

* auto-rebuild stale ops container without mise ([0ee2991](https://github.com/syscode-labs/omni-on-unraid/commit/0ee2991638219418d244f5bf7ee6f368d3b221ce))
* auto-trust mise config in container tasks ([bd18335](https://github.com/syscode-labs/omni-on-unraid/commit/bd183352e953a80e85ade83ab3fbfb27c1cf5821))
* fail infra-check on ssh transport errors before image check ([db284d0](https://github.com/syscode-labs/omni-on-unraid/commit/db284d0d27a7ba912580a573b1891f484cee3d91))
* make ctr infra apply use local base-image cache for libvirt ([f225fc4](https://github.com/syscode-labs/omni-on-unraid/commit/f225fc494e0f37cc0c268d30680661ca096dadd1))
* mount host home path in ops container for absolute key paths ([6563e68](https://github.com/syscode-labs/omni-on-unraid/commit/6563e688ab1f897fe535cf7759b1cf07bf0df761))
* recover bridged vm networking and harden remote omni deployment flow ([cc8d03f](https://github.com/syscode-labs/omni-on-unraid/commit/cc8d03faf69c93fef07e3eda78d8d412dcfdb7aa))
