# Changelog

## [0.3.0](https://github.com/syscode-labs/omni-on-unraid/compare/v0.2.1...v0.3.0) (2026-09-05)


### Features

* add Omni GitHub Actions runner ([#23](https://github.com/syscode-labs/omni-on-unraid/issues/23)) ([ba380d6](https://github.com/syscode-labs/omni-on-unraid/commit/ba380d658a77355bec3ccd063ab1b89fdfc5f473))
* add unattended Unraid release receiver ([74c3e0f](https://github.com/syscode-labs/omni-on-unraid/commit/74c3e0f65e62dee1d0fb82c503e420aabda4594d))
* add unattended Unraid release receiver ([082c040](https://github.com/syscode-labs/omni-on-unraid/commit/082c040546b726bbb7c212c0c0cd0d48866c7382))
* **image-factory:** deploy on-prem registry + tailnet sidecar with signed composite catalog ([0f252e8](https://github.com/syscode-labs/omni-on-unraid/commit/0f252e8c847a01684eb85d272f824164791026d0))
* support break-glass configs ([84ba174](https://github.com/syscode-labs/omni-on-unraid/commit/84ba17479febaa1c1d6a0972e2137774f7a44b3f))
* support break-glass configs ([2d4b8d3](https://github.com/syscode-labs/omni-on-unraid/commit/2d4b8d3bd92f3025f066fe5bd297286135102c2d))
* **terraform:** manage Omni provider NAT NIC ([ffdcefa](https://github.com/syscode-labs/omni-on-unraid/commit/ffdcefad2efb0c0429c052674eff051d5a63ad2f))


### Bug Fixes

* activate payload release clients ([2466199](https://github.com/syscode-labs/omni-on-unraid/commit/2466199804251f79e97ab08df076e57f1046ae1c))
* activate payload release clients ([08c66b9](https://github.com/syscode-labs/omni-on-unraid/commit/08c66b9d3c172d361acb039749dba158aa42978d))
* bind Caddy SNI Kubernetes proxy locally ([97b5a30](https://github.com/syscode-labs/omni-on-unraid/commit/97b5a30fe2313383844c57dc21ce693c01c778ed))
* bind Caddy SNI Kubernetes proxy locally ([7c5da6d](https://github.com/syscode-labs/omni-on-unraid/commit/7c5da6d3db4c00133f1494256aef3aa9d18da633))
* classify pre-mutation release failures ([f121ba4](https://github.com/syscode-labs/omni-on-unraid/commit/f121ba4e32d57dc1f50cd882553a5565162c5c8f))
* execute inline mise tasks with bash ([5bdeaa8](https://github.com/syscode-labs/omni-on-unraid/commit/5bdeaa8102a8a8827100a49d690193bf87667855))
* execute inline mise tasks with Bash ([dbc4098](https://github.com/syscode-labs/omni-on-unraid/commit/dbc409848229410093e43ac0ed89d1de4a7705d2))
* **factory:** route libvirt nodes to image factory ([2a718a2](https://github.com/syscode-labs/omni-on-unraid/commit/2a718a2dc9e2d6d4dec0ca8d1b7adc73734f8eeb))
* harden Unraid release dispatch ([b165135](https://github.com/syscode-labs/omni-on-unraid/commit/b1651352995e0283d7284bcdb71553c0f4d9a458))
* install custom installer via cluster config patch ([47af661](https://github.com/syscode-labs/omni-on-unraid/commit/47af661270fc21d7622f88d2637fdfdf2ead1a1b))
* install custom installer via cluster config patch ([ea389d5](https://github.com/syscode-labs/omni-on-unraid/commit/ea389d5c6d1b09580cf3a20297dc4cba83fb373f))
* install Go for release receiver ([69a5bba](https://github.com/syscode-labs/omni-on-unraid/commit/69a5bba21df8a74e2c1b28fab9c5588a472d42b3))
* install Go for release receiver ([9c3e6fe](https://github.com/syscode-labs/omni-on-unraid/commit/9c3e6fe7f426efa5ec90be2de6b1a07573c389ed))
* install mise before release runtime check ([4d22ce3](https://github.com/syscode-labs/omni-on-unraid/commit/4d22ce3d70a65044f729b67410c4100880a459f0))
* install mise before release runtime check ([95e337b](https://github.com/syscode-labs/omni-on-unraid/commit/95e337ba32f691082e9b101f907d2445638c9468))
* make provider status compatible with mise ([80dd48b](https://github.com/syscode-labs/omni-on-unraid/commit/80dd48b28e7f185a91ffb854a6ac19a0882d1dcf))
* make provider status compatible with mise ([f2dd44f](https://github.com/syscode-labs/omni-on-unraid/commit/f2dd44fd79611cf5215f33a54d70e13729ce78cd))
* **omni:** persist Imp node opt-in label ([bb4852c](https://github.com/syscode-labs/omni-on-unraid/commit/bb4852cca22bf35f56a9e67100856906f5f6137a))
* **omni:** persist Imp node opt-in label ([7a44454](https://github.com/syscode-labs/omni-on-unraid/commit/7a4445437bd20cad8edfb56709a0e28c5d84a15d))
* **omni:** restore Imp node label patch ([#21](https://github.com/syscode-labs/omni-on-unraid/issues/21)) ([b41285d](https://github.com/syscode-labs/omni-on-unraid/commit/b41285df5b07877c3093bb4b1decfd185f752bc9))
* **omni:** validate configured provider artifact ([73c532e](https://github.com/syscode-labs/omni-on-unraid/commit/73c532e0c85788f2a99ba1e210bafdb82af02984))
* **omni:** validate configured provider artifact ([9eb912b](https://github.com/syscode-labs/omni-on-unraid/commit/9eb912b090855171f0b650e08324e9394f57c3b4))
* pass Compose profiles through sudo ([#24](https://github.com/syscode-labs/omni-on-unraid/issues/24)) ([d13ee51](https://github.com/syscode-labs/omni-on-unraid/commit/d13ee516f4620b28b50750e58e4e96cacbf6db8a))
* persist Omni runner identity ([#25](https://github.com/syscode-labs/omni-on-unraid/issues/25)) ([d2f4745](https://github.com/syscode-labs/omni-on-unraid/commit/d2f47450504b5a096a5bc4557a409286394ed4b3))
* preserve 1.13 runtime defaults on Talos 1.14 ([d032dd2](https://github.com/syscode-labs/omni-on-unraid/commit/d032dd28f706ac290d18cfc15134e99fa348e2ab))
* preserve 1.13 runtime defaults on Talos 1.14 ([202539a](https://github.com/syscode-labs/omni-on-unraid/commit/202539a9c99a722f3ec6f210cbefd52d497cbcb6))
* **release:** bind Unraid rollout to live provider runtime ([96a964c](https://github.com/syscode-labs/omni-on-unraid/commit/96a964c4a2ce71bf55c6c07a598fc281829226cb))
* remove stale mise runtime assertion ([668d072](https://github.com/syscode-labs/omni-on-unraid/commit/668d072d873d5354e5be8856e8c4ae2492ab45c0))
* remove stale mise runtime assertion ([29974ac](https://github.com/syscode-labs/omni-on-unraid/commit/29974ac567bb0a21470d0fbc5541b45497874e58))
* report release attempt recovery state ([0d8c56b](https://github.com/syscode-labs/omni-on-unraid/commit/0d8c56bb6694e2b750a46ee2e2f18f79332db1bb))
* run inline mise tasks with bash ([63db14b](https://github.com/syscode-labs/omni-on-unraid/commit/63db14b5af31497980cc54249b2741c46048e5ce))
* select omni-runner by runner group ([ee83075](https://github.com/syscode-labs/omni-on-unraid/commit/ee830758e7cf60cdd7205e8ae2be6a88a351d11c))

## [0.2.1](https://github.com/syscode-labs/omni-on-unraid/compare/v0.2.0...v0.2.1) (2026-08-09)


### Bug Fixes

* **compose:** emit SQLITE_STORAGE_PATH alongside SECONDARY_STORAGE_PATH ([53b4906](https://github.com/syscode-labs/omni-on-unraid/commit/53b4906dc5ff374243f50720932cbd976051dcd0))
* **omni:** auto-evict stuck cluster members before sync ([7b41831](https://github.com/syscode-labs/omni-on-unraid/commit/7b41831a7e4453738021873573d58d65cce938cb))
* **render:** update upstream Omni compose base URL ([07543de](https://github.com/syscode-labs/omni-on-unraid/commit/07543de8fbe7d1bc8a878455fa8db0f9a3668e25))

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
