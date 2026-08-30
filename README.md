# ios-sdk

Native iOS studio for [Livo](https://livo.tv). Swift Package Manager products:

| Product | Role |
| --- | --- |
| `LivoStudioAPI` | Public media-svc client: host redeem, guest join, control tokens |
| `LivoStudioKit` | SwiftUI room on [Cloudflare RealtimeKit Core](https://github.com/cloudflare/realtimekit-ios-core) |

**Never put an org API key (`lk_…`) in the iOS binary.** Mint host/guest tokens on your backend with `@livo-tv/sdk/server` (or `POST /streams/:id/studio/host-session`), then hand the tokens to the app.

## Add the package

```swift
dependencies: [
    .package(url: "https://github.com/livo-tv/ios-sdk.git", from: "1.0.0"),
]
```

Minimum iOS 17. Add `NSCameraUsageDescription` and `NSMicrophoneUsageDescription`.

## Partner host

```swift
import LivoStudioKit

LivoHostStudioView(hostToken: mintedHostToken) { event in
    // .joined / .live / .ended / .left
}
.studioTheme(StudioTheme.livo)
```

## Partner guest

```swift
LivoGuestStudioView(guestToken: mintedGuestToken)
```

## First-party / already-minted session

```swift
StudioRoomView(session: session, apiURL: mediaURL)
```

`session` is the JSON from `POST /streams/:id/studio/session` (JWT) or
`POST /public/studio/host/:token`.

## Backend (Node)

```ts
import { createLivoServerClient } from "@livo-tv/sdk/server";

const livo = createLivoServerClient({ apiKey: process.env.LIVO_API_KEY! });
const { hostToken, guestToken, hostUrl, guestUrl } = await livo.mintHostSession(
  streamId,
  { displayName: "Host" },
);
```

Send `hostToken` / `guestToken` to the iOS app. The `*Url` fields still open the web studio if you need a fallback.

## Versioning

Releases are cut by semantic-release on `main` (stable `vX.Y.Z`) and `dev` (prerelease `vX.Y.Z-rc.N`). SPM consumers pin a git tag — never a branch. See [docs/RELEASE_RUNBOOK.md](docs/RELEASE_RUNBOOK.md).

## Quality gate

```bash
./scripts/ci-check.sh
```

## Screen share

Requires a ReplayKit Broadcast Upload Extension in the **host app**. See [docs/SCREEN_SHARE.md](docs/SCREEN_SHARE.md).
