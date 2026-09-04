# Promote dest → main

Runbook: [`harness/platform/promote-dev-to-main.md`](../../platform/promote-dev-to-main.md)
(workspace) or the same path inside a harness checkout.

## Resolve the repo

1. Confirm this folder has `origin/dev` and `origin/main`. Harness does not
   — edit `main` only. e2e has dest but no semantic-release.
2. Do not promote every sibling. Libraries (`blocks`, `sdk`, `ios-sdk`)
   before consumers (`app`, `admin`, `player`, `ios-app`).

## Preflight

```bash
git fetch origin main dest
git log --oneline origin/main..origin/dev
git log --oneline origin/dev..origin/main
```

- dest ahead, 0 behind → open the promote PR.
- dest behind → merge `main` into `dev` first; wait for CI.
- dest == main → already promoted; stop.

Run that repo's quality gate. Do not add product commits on the promote
branch.

## Merge

Open a PR dest → `main`. Merge with a **merge commit** (never squash —
semantic-release on `main` needs the original `feat:` / `fix:` commits).

Wait for `release.yml` on `main`. Confirm the stable tag (and npm `latest`
for libraries).

## After release — dest ← `main` (required)

Promote is **not done** when `main` is green. Semantic-release may write
`chore(release): X.Y.Z` only on `main`. Merge `main` back into dest so
the next dest → `main` PR does not conflict on `package.json` /
CHANGELOG (ADR 0026).

- Fast-forward dest when dest has nothing new; otherwise a merge commit.
- Do **not** re-promote a dest-sync-only merge.
- Same fold after a hotfix off `main`.
- Wait for dest CI.

Never hand-bump `version`. Never `npm publish` / local-deploy.

## Path to `main`

In repos with `dev`, product work (including library pins) lands on dest.
`main` is reached only by promoting dest. A PR off `main` is a **hotfix**
and should be unusual. After a hotfix or a stable `chore(release)`, merge
`main` back into dest before any other dest work.

## Consumers after a library cut

Replace an exact `X.Y.Z-rc.N` pin with `^X.Y.Z` and refresh the lockfile
**on dest**. Promote dest → `main` when prod should pick it up. Do not
open a parallel pin PR off `main` for the same bump. A `^` range on an
older minor will not update until the lockfile does. Update `AGENTS.md`
`## Learnings` when it names the pin.
