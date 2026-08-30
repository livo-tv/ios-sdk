# Livo iOS Studio SDK

Embed [Livo](https://livo.tv) Studio in a native iOS app. Same product as the web embed (`@livo-tv/sdk/studio`): host goes live, guests wait, chat, and join the stage.

Distributed as a **Swift package**. Versions are git tags (`v1.2.3`). This repo is not published to npm.

| Product | Add this | Role |
| --- | --- | --- |
| `LivoStudioKit` | yes | SwiftUI room (host, guest, theme) |
| `LivoStudioAPI` | pulled in by Kit | HTTP client for public studio endpoints |

**Never put an org API key (`lk_…`) in the iOS binary.** Mint `hostToken` / `guestToken` on your backend, then hand those short-lived tokens to the app.

## Requirements

- iOS 17+
- Xcode 16+ (Swift 5.9 tools)
- Camera and microphone usage descriptions in the **host app** Info.plist
- A Livo org API key on your **server** only

## Add the package

### Xcode

1. File → Add Package Dependencies…
2. URL: `https://github.com/livo-tv/ios-sdk.git`
3. Dependency rule: **Up to Next Major** from `1.0.0`
4. Add product **LivoStudioKit** to your app target

### `Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/livo-tv/ios-sdk.git", from: "1.0.0"),
],
```

Then depend on `.product(name: "LivoStudioKit", package: "ios-sdk")`.

Pin a **version**, never `branch: "main"`. Prerelease tags (`1.2.3-rc.1`) are not selected by `from: "1.0.0"`.

## Info.plist

```xml
<key>NSCameraUsageDescription</key>
<string>Livo Studio uses the camera so you can appear on the broadcast.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Livo Studio uses the microphone so guests can hear you.</string>
```

## Host

```swift
import LivoStudioKit

LivoHostStudioView(hostToken: mintedHostToken) { event in
    switch event {
    case .joined, .live, .ended, .left:
        break
    }
}
.studioTheme(StudioTheme.livo)
```

The host token is **single-use** and expires (typically 10 minutes). Redeem it when you present the view.

## Guest

```swift
LivoGuestStudioView(guestToken: mintedGuestToken)
    .studioTheme(StudioTheme(primary: Color(red: 0.15, green: 0.39, blue: 0.92)))
```

Guests enter a lobby (display name + device check) and join when the meeting is ready.

## Theme

`StudioTheme` matches the web embed object: `primary`, `background`, `foreground`, `radius`, `mode` (`.light` / `.dark` / `.system`). `StudioTheme.livo` is the default.

## Point at another API host

Production is `https://media-svc.livo.tv`. For Livo’s Dev account:

```swift
LivoHostStudioView(
    hostToken: token,
    apiURL: URL(string: "https://media-svc.livo-tv.workers.dev")!
)
```

## Mint tokens on your backend

Node / Workers with [`@livo-tv/sdk`](https://www.npmjs.com/package/@livo-tv/sdk):

```ts
import { createLivoServerClient } from "@livo-tv/sdk/server";

const livo = createLivoServerClient({ apiKey: process.env.LIVO_API_KEY! });
const { hostToken, guestToken, hostUrl, guestUrl } = await livo.mintHostSession(
  streamId,
  { displayName: "Host" },
);
```

Or `POST /streams/:id/studio/host-session` with `X-Api-Key`. Send `hostToken` / `guestToken` to the iOS app. `hostUrl` / `guestUrl` still open the web studio if you need a fallback.

## Already have a session JSON

First-party apps that called `POST /streams/:id/studio/session` (org JWT) can skip redeem:

```swift
StudioRoomView(session: session, apiURL: mediaURL)
```

`session` is the JSON from that route or from `POST /public/studio/host/:token`.

## Screen share

The Screen share button is in the host toolbar. iOS will not capture the display until **your app** ships a ReplayKit Broadcast Upload Extension. The SDK cannot add that target. See [docs/SCREEN_SHARE.md](docs/SCREEN_SHARE.md).

## Example

[Examples/StudioExample](Examples/StudioExample) is a small SwiftUI app: paste a host or guest token and open the room. Open `Examples/StudioExample/StudioExample.xcodeproj` (it depends on this package via a local path).

## Versioning

| Branch | Tag | Meaning |
| --- | --- | --- |
| `main` | `vX.Y.Z` | stable |
| `dev` | `vX.Y.Z-rc.N` | prerelease |

Releases are cut by conventional commits + semantic-release. See [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
