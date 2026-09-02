# Verify e2e

Runbook for `/verify-e2e` after a user-visible or cross-service change.

## Resolve the area

1. Read `e2e/COVERAGE.md` (workspace) or this repo's Identity **E2E areas**.
2. Pick the matching `@area` tag (`@auth`, `@streams`, `@vods`, `@keys`,
   `@admin`, `@members`, `@trash`, `@curtains`, `@settings`, `@licenses`,
   `@partners`, `@player`, `@metrics`, `@notifications`, `@docs`).
3. Note the tier: `prod-safe` / `cheap` / `live-media` / `dev-only`.

## Environment matrix

| Env                  | When                     | Command                                          |
| -------------------- | ------------------------ | ------------------------------------------------ |
| Prod cheap (default) | Agent verification today | `cd e2e && pnpm test:prod:verify --grep @<area>` |
| Prod smoke only      | No password secrets      | `cd e2e && pnpm test:prod`                       |
| Live media           | User explicitly asked    | `cd e2e && pnpm test:live --grep @<area>`        |
| Dev / local          | Stack is actually up     | `cd e2e && pnpm test:dev --grep @<area>`         |

Dev hosts are 404 until a stack ships. Do not treat that as a product failure.

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
