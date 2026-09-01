# ios-sdk release runbook

Human setup for semantic-release git tags. Agents do not commit, push, or create tags from a laptop.

The GitHub repo is **public**. Third-party apps resolve `https://github.com/livo-tv/ios-sdk.git` with no token. There is no npm publish and no SPM registry secret.

## What the pipeline does

One workflow: `.github/workflows/ci.yml`. macos-15 runs `./scripts/ci-check.sh` on pull requests, `workflow_dispatch`, and push to `main`/`dev`. The Ubuntu `release` job runs only after that check succeeds on `main` or `dev` (semantic-release git tags, no Xcode).

| Branch | Tag | GitHub Release | npm |
| --- | --- | --- | --- |
| `main` | `vX.Y.Z` | stable | never |
| `dev` | `vX.Y.Z-rc.N` | prerelease | never |

SPM consumers pin a tag, for example `.package(url: "https://github.com/livo-tv/ios-sdk.git", from: "1.0.0")`.

Conventional commits are required (`feat:` → minor, `fix:` → patch, `BREAKING CHANGE` → major). `chore:` / `docs:` / `ci:` do not cut a release.

## First tag

`v1.0.0` is already on `main`. Later releasable commits cut `v1.1.0`, `v1.0.1`, and so on.

If the `release` job no-ops, the latest commit was not releasable — add a `feat:` or `fix:` and push again.

## Optional `dev` branch

Pushing releasable commits to `dev` cuts `vX.Y.Z-rc.N`. `from: "1.0.0"` skips prereleases.

## Day-2

- Do not hand-edit `package.json` `version` or create tags locally.
- Bump `realtimekit-ios-core` only with a semver pin in `Package.swift` (not `branch: "main"`).
- Re-run a stuck release with **Actions → CI → Run workflow** on the branch that has the unreleased commits.
- Keep the README partner-facing. Do not document first-party deploy secrets here.
