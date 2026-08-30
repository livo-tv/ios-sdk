# iOS screen share (ReplayKit)

Partner host apps that want the in-room **Screen share** button to capture the
display must ship a ReplayKit Broadcast Upload Extension. LivoStudioKit only
calls `meeting.localUser.enableScreenShare()` on RealtimeKit Core. The SDK
cannot add the extension target for you.

## 1. Add a Broadcast Upload Extension

In Xcode: File → New → Target → **Broadcast Upload Extension**.

Use a handler that subclasses RealtimeKit's sample handler:

```swift
import RealtimeKit

class SampleHandler: RtkSampleHandler {}
```

## 2. App Group

1. Add the **App Groups** capability to the app target and the extension.
2. Use the same identifier, for example `group.your.bundle.studio`.
3. Put this in **both** Info.plist files:

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

`StudioToolbar` already exposes a Screen share button. It is a no-op until the
extension is installed; RealtimeKit then presents the system broadcast picker.

See [RealtimeKit local participant — screen share (iOS)](https://developers.cloudflare.com/realtime/realtimekit/core/local-participant/).
