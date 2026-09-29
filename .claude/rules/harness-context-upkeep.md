# Harness context upkeep

When your task changes any of the following, update context **in the same task** before claiming done:

- Cross-service API / RPC / JWT / webhook / spawn contract
- Wrangler bindings (services, D1, R2, KV) or env vars consumers need
- Quality-gate scripts, coverage thresholds, deploy target
- A durable gotcha future agents will rediscover the hard way

## Where to write

1. This repo's `AGENTS.md` → `## Learnings` (repo-specific).
2. `harness/platform/learnings/<topic>.md` for a workspace-level fact. Root `AGENTS.md` → `## Learnings` is an index of those files. Add an index line only when you create a new topic file.
3. `harness/platform/` docs when the fact is a contract, infra note, or convention.
4. `harness/platform/decisions/` new ADR for a durable contract or architecture choice.
5. Run `node harness/scripts/audit.mjs` if wrangler/package scripts changed, then `sync.mjs` / `check.mjs` when practical.

## Context budget

- Send broad exploration, large doc reads, CI-failure investigation, and e2e runs to a subagent (explore or generalPurpose). It returns a summary.
- Grep first, then read with an offset and limit. Do not re-read a file already in context.
- When a phase ends, start a new chat from the plan file in `.cursor/plans/` instead of carrying the whole history.

## Do not

- Leave contract changes only in chat history
- Paste workspace facts back into root `AGENTS.md` Learnings. That section stays an index.
- Edit managed `<!-- harness:begin managed -->` blocks, `CLAUDE.md`, or `.claude/` by hand — change harness sources and re-sync
