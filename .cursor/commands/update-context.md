# Update context

End-of-task pass to keep the Livo harness current.

## Steps

1. Review the diff of files you changed in this session.
2. For each durable fact (contract, binding, env var, gotcha, gate change):
   - Append to the touched repo's `AGENTS.md` → `## Learnings`, **or**
   - Update `harness/platform/01-topology.md` / `02-contracts.md` / `03-infra.md` / `04-conventions.md` as appropriate.
3. If the change is a durable architecture/contract decision, add `harness/platform/decisions/NNNN-slug.md`.
4. If wrangler configs, package scripts, or remotes changed:
   ```bash
   node harness/scripts/audit.mjs
   node harness/scripts/sync.mjs --dry-run
   node harness/scripts/sync.mjs
   node harness/scripts/check.mjs
   ```
5. Do **not** local-deploy. Local/desktop agents: do not commit/push unless the user asks. Cloud agents: commit/push context updates with the rest of the branch when that is part of the task.
