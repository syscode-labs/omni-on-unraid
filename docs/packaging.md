# Packaging

This repo ships the `omni-on-unraid` operator TUI.

## Nix

Run from this repository:

```bash
nix run .#omni-on-unraid
nix build .#omni-on-unraid
```

The default flake package and app are the TUI. `omnictl` remains available as:

```bash
nix build .#omnictl
```

## Homebrew Tap

Release automation publishes this public tool cask to:

```text
syscode-labs/homebrew-public
```

Public tools use `syscode-labs/homebrew-public`. Private tools can use
`syscode-labs/homebrew-private`. Each tap can hold many formulae and casks.

Because this repository and its release assets are public, the cask can download
release archives without a GitHub token.

Required setup:

1. Create `syscode-labs/homebrew-public`.
2. Add a repository secret named `HOMEBREW_TAP_TOKEN` to this repo.
3. The token needs contents write access to `syscode-labs/homebrew-public`.

Install after a release:

```bash
brew install --cask syscode-labs/public/omni-on-unraid
```

## Semantic Release

Release PRs are created by Release Please from Conventional Commits:

```text
fix: patch release
feat: minor release
feat!: major release
```

When the release PR is merged, the Release Please workflow creates the GitHub
release and runs GoReleaser in the same CI job. GoReleaser uploads
darwin/linux amd64/arm64 archives, uploads `checksums.txt`, and updates the
Homebrew public tap cask.

Recommended setup:

1. Add `HOMEBREW_TAP_TOKEN` with contents write access to
   `syscode-labs/homebrew-public`.
2. Add `RELEASE_PLEASE_TOKEN` as a fine-grained PAT with access to this repo if
   release PRs should trigger normal CI checks. If unset, Release Please falls
   back to `GITHUB_TOKEN`.
3. Enable "Allow GitHub Actions to create and approve pull requests" in repo
   Actions settings if release PR creation is blocked.
4. Replace long-lived PAT secrets with a Syscode GitHub App. Store the app id
   and private key as Actions secrets, mint short-lived installation tokens in
   CI, and pass those tokens to Release Please and GoReleaser.

## Manual Release Fallback

The manual release workflow can run GoReleaser against a chosen ref:

- GitHub Actions -> Release -> Run workflow
- choose `ref`

Local checks:

```bash
go test ./...
goreleaser check
goreleaser release --snapshot --clean
```
