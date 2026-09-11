# Portal workflows

## Description
Validation, automatic version tagging and CurseForge packaging for Portal.

## Purpose
Keep the existing release sequence while stopping incomplete bundles before tagging or upload.

## Implementation
`validate.yml` fetches LibOrbitUI's immutable `.pkgmeta` pin and checks the triggering checkout with pinned Python/Lua parser versions. `auto-tag.yml` requires validation before its existing commit-count tag step; `release.yml` independently requires validation before the standard packager fetches that same external and packages a pushed tag. No release is dispatched by these checks.

Both callers explicitly forward `ORBIT_PAT` to reusable validation. Validation and release checkouts disable persisted checkout credentials, then configure GitHub CLI's Git helper. Orbit-Libs is public; the existing credential policy keeps `GH_TOKEN` available during dependency fetching and packaging. Release publishing still uses the addon repository token and CurseForge credentials.

Packaging uses `-u` to preserve LF text bytes, keeping the final embedded files consistent with the checked content manifest.

## Gotchas
- Fork and Dependabot pull requests receive an explicit notice instead of the credentialed package check. They receive no library token, and this workflow never uses `pull_request_target`; trusted validation must pass before a version can be tagged or published.
- The ignored local library junction never enters a clean-checkout package. Pin changes and generated content-manifest changes must agree before validation passes.
- A source check does not certify protected game execution. In-game acceptance and release ownership remain with the human.

## References
`../../.scripts/README.md`, `../../README.md`.
