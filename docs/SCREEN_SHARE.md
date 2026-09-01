# iOS screen share (ReplayKit)

Partner host apps that want the in-room **Screen share** button to capture the
display must ship a ReplayKit Broadcast Upload Extension. LivoStudioKit only
calls `meeting.localUser.enableScreenShare()` on RealtimeKit Core. The SDK
cannot add the extension target for you.

iOS always shows the **system** broadcast picker. There is no silent in-app
capture. With the extension installed, the picker lists **Livo** instead of
Zoom / Photos / etc.

The first-party app (`ios-app`) already ships `LivoBroadcast`
(`tv.livo.app.broadcast`) with App Group `group.tv.livo.app`.

## 1. Add a Broadcast Upload Extension

In Xcode: File → New → Target → **Broadcast Upload Extension**.

RealtimeKit Core 3.1.0 does **not** export `RtkSampleHandler` from the
XCFramework. Vendor the handler (see `ios-app/ios-livo/LivoBroadcast/`) or
subclass if a later Core release exports it:

```swift
import ReplayKit

@objc(SampleHandler)
final class SampleHandler: RtkSampleHandler {}
```

## 2. App Group

1. Create the App Group in [Apple Developer](https://developer.apple.com/account/resources/identifiers/list/applicationGroup) and enable it on the app and extension App IDs. Entitlements in the repo are not enough — the group must exist on the team and the **device provisioning profile** must include it. If it does not, RealtimeKit logs a CFPrefs `group.*` failure and `ScreenCaptureController#startCapture` throws; screen share never starts.
2. Add the **App Groups** capability to the app target and the extension.
3. Use the same identifier, for example `group.your.bundle.studio`.
4. Put this in **both** Info.plist files:

```xml
<key>RTKRTCAppGroupIdentifier</key>
<string>group.your.bundle.studio</string>
```

And only in the **app** Info.plist:

```xml
<key>RTKRTCScreenSharingExtension</key>
<string>YOUR.EXTENSION.BUNDLE.ID</string>
```

## 3. Call the SDK

`StudioToolbar` exposes a Screen share button. Until the extension is
installed the system picker has nothing from your app. After it is installed,
RealtimeKit presents the picker and `screenShareOn` follows
`onScreenShareUpdate`. A failed start (`onScreenShareStartFailed`) rolls the
toggle back and toasts.

See [RealtimeKit local participant — screen share (iOS)](https://developers.cloudflare.com/realtime/realtimekit/core/local-participant/).

## Background audio

The host app Info.plist must also declare `UIBackgroundModes` → `audio`. Without
it iOS suspends the process a few seconds after backgrounding and the
RealtimeKit socket dies. See the [README Info.plist section](../README.md#infoplist).
