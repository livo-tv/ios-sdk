# ios-sdk release runbook

Human setup for semantic-release git tags. Agents do not commit, push, or create tags from a laptop.

## What the pipeline does

| Branch | Tag | GitHub Release | npm |
| --- | --- | --- | --- |
| `main` | `vX.Y.Z` | stable | never |
| `dev` | `vX.Y.Z-rc.N` | prerelease | never |

SPM consumers pin a tag, for example `.package(url: "https://github.com/livo-tv/ios-sdk.git", from: "1.0.0")`.

Conventional commits are required (`feat:` → minor, `fix:` → patch, `BREAKING CHANGE` → major). `chore:` / `docs:` / `ci:` do not cut a release.

## Bootstrap (first tag)

The repo starts with `package.json` version `0.0.0-development` and no tags. First releasable commit on `main` becomes `v1.0.0`.

1. Review the working tree. Include a conventional commit that is releasable (`feat:` is enough).
2. Push `main` to `https://github.com/livo-tv/ios-sdk.git`.
3. Confirm `.github/workflows/release.yml` succeeds and tag `v1.0.0` exists.
4. Only then push `ios-app` changes that depend on this package by version.

If `release.yml` no-ops, the latest commit was not releasable — add a `feat:` or `fix:` and push again.

## Optional `dev` branch

Create `dev` when you want RC tags. Pushing releasable commits to `dev` cuts `vX.Y.Z-rc.N`. `ios-app` does not consume RC tags (`from: "1.0.0"` skips prereleases).

## Day-2

- Do not hand-edit `package.json` `version` or create tags locally.
- Bump `realtimekit-ios-core` only with a semver pin in `Package.swift` (not `branch: "main"`).
- Re-run a stuck release with **Actions → Release → Run workflow** on the branch that has the unreleased commits.

## ios-app consumer

`ios-app` resolves this repo as a private SPM package. After `v1.0.0` exists, add a fine-grained PAT (Contents: read on `livo-tv/ios-sdk`) as `IOS_SDK_READ_TOKEN` on `livo-tv/ios-app`. Details: `ios-app/docs/RELEASE_RUNBOOK.md`.
