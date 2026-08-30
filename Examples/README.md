# Studio example

Minimal SwiftUI host/guest shell for [LivoStudioKit](../README.md).

1. Open `StudioExample/StudioExample.xcodeproj` in Xcode.
2. Select an iOS 17+ simulator or device.
3. Mint `hostToken` / `guestToken` on your backend (`POST /streams/:id/studio/host-session` or `@livo-tv/sdk/server`). Do not paste an `lk_` API key into the app.
4. Run, paste a token, open Host or Guest.

The project depends on this repo via a local Swift package path (`../..`). After you add the package to your own app, use the git URL and a version instead.
