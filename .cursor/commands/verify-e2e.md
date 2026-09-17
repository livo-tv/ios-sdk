# Verify e2e

Runbook for `/verify-e2e` after a user-visible or cross-service change.

## Resolve the area

1. Read `e2e/COVERAGE.md` (workspace) or this repo's Identity **E2E areas**.
2. Pick the matching `@area` tag (`@auth`, `@streams`, `@vods`, `@keys`,
   `@admin`, `@members`, `@environments`, `@trash`, `@curtains`, `@settings`,
   `@licenses`, `@partners`, `@player`, `@metrics`, `@notifications`, `@docs`).
3. Note the tier: `prod-safe` / `cheap` / `live-media` / `dev-only`.

## Environment matrix

| Env                | When                                                                 | Command                                            |
| ------------------ | -------------------------------------------------------------------- | -------------------------------------------------- |
| Preview (ADR 0027) | PR into `dev` is open — preferred for UI/journey on the unmerged SHA | `cd e2e && pnpm test:preview --slug <slug>`        |
| Prod cheap         | No open preview, or after the change is on prod                      | `cd e2e && pnpm test:prod:verify --grep @<area>`   |
| Prod smoke only    | No password secrets                                                  | `cd e2e && pnpm test:prod`                         |
| Live media         | User explicitly asked                                                | `cd e2e && pnpm test:live --grep @<area>`          |
| Dev                | Deployed `*.livo-tv.workers.dev`                                     | `cd e2e && pnpm test:dev --grep @<area>`           |
| Local              | `pnpm --dir harness dev` up                                          | `cd e2e && E2E_ENV=local pnpm test --grep @<area>` |

When a PR into `dev` is open, wait for the `<!-- livo-preview-stack -->`
comment (`/healthz` ok). For an `auth-svc` stack, confirm
`GET {auth-svc-stack}/api/auth/login-method?email=e2e_operator@livo.tv`
returns `{ method: "password" }`, then sign in on
`https://<slug>-auth.livo-tv.workers.dev/login` with Cursor Cloud password
secrets (clean browser profile — cookies share `.livo-tv.workers.dev` with
stable-dev). Passkeys / Google / OTP do not work on preview aliases. Prod
cheap cannot validate the unmerged branch.

Dev hosts are 404 until `harness/platform/dev-stack-handoff.md` is done. Local
OTP uses wrangler `--local` KV (no `CF_API_TOKEN`). `pnpm probe:hls <url>`
checks ladder + AAC-LC.

## Interpret results

- **Green** — verification passed. Task may be marked done.
- **Skipped (`allowWrites` / `canReadOtp` / `env.name === "prod"`)** — expected
  for onboarding, licenses, and partners on prod. Do not invent a prod write
  for those. If the task needed that journey, add or keep a `required-missing`
  COVERAGE.md row.
- **Red** — not done. Fix the product or the spec, or report the failure.
- **No spec** — add a spec or a `required-missing` row in the same task.

## Hands and eyes

```bash
cd e2e
pnpm snap customer /streams
pnpm snap operator https://admin.livo.tv/users
pnpm snap guest https://player.livo.tv/<id>
pnpm probe GET /streams
```

Never run `@live-media` unless the user asked. Never toggle persona
password-login. Never read prod KV.
