{
  description = "Omni-on-Unraid tooling";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-darwin" "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      omniVersion = "v1.5.8";
      tuiVersion = "0.1.0";
      omnictlAssets = {
        x86_64-darwin = {
          asset = "omnictl-darwin-amd64";
          hash = "sha256-3DejCNXUgPBcV7xl1i6iqcd1Yq4iQPJLYy1EhnXEMyg=";
        };
        aarch64-darwin = {
          asset = "omnictl-darwin-arm64";
          hash = "sha256-JpynkoI5lS2e2amX1TxN2wcoy91oMlt77IcO+9Ds8Q4=";
        };
        x86_64-linux = {
          asset = "omnictl-linux-amd64";
          hash = "sha256-hMwvqlHZ12/SLGBsE4sgpllnpW23m1AmiSoYMydNoFU=";
        };
        aarch64-linux = {
          asset = "omnictl-linux-arm64";
          hash = "sha256-BVCf1Eb/1aaxsnmyv2HGEeLjiQb5IHDE6RumadvVpLs=";
        };
      };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          asset = omnictlAssets.${system};
          omni-on-unraid = pkgs.buildGoModule {
            pname = "omni-on-unraid";
            version = tuiVersion;
            src = ./.;
            modRoot = ".";
            subPackages = [ "cmd/omni-tui" ];
            vendorHash = "sha256-qA/ZXadmuq/uUQns5JMuctaMhPYYcuvzPh7bueFQFZI=";
            ldflags = [
              "-s"
              "-w"
            ];
            postInstall = ''
              mv "$out/bin/omni-tui" "$out/bin/omni-on-unraid"
            '';
            meta = {
              description = "Operator TUI for Omni-on-Unraid";
              homepage = "https://github.com/syscode-labs/omni-on-unraid";
              license = pkgs.lib.licenses.mit;
              mainProgram = "omni-on-unraid";
            };
          };
        in
        {
          inherit omni-on-unraid;
          omnictl = pkgs.stdenvNoCC.mkDerivation {
            pname = "omnictl";
            version = omniVersion;
            src = pkgs.fetchurl {
              url = "https://github.com/siderolabs/omni/releases/download/${omniVersion}/${asset.asset}";
              hash = asset.hash;
            };
            dontUnpack = true;
            installPhase = ''
              install -Dm755 "$src" "$out/bin/omnictl"
            '';
          };
          default = omni-on-unraid;
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/omni-on-unraid";
        };
        omni-on-unraid = self.apps.${system}.default;
      });

      devShells = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          omni = pkgs.mkShell {
            packages = [
              pkgs.go_1_25
              pkgs.goreleaser
              pkgs.kubectl
              pkgs.kustomize
              pkgs.sops
              self.packages.${system}.omnictl
            ];
          };
          default = self.devShells.${system}.omni;
        });
    };
}
