# Spike: RealtimeKit iOS Core + Livo studio tokens

Validated against Cloudflare RealtimeKit Core docs (2026-08-24) and the
`realtimekit-ios-core` `Package.swift` on `main` (binary XCFramework **3.1.0**).
A live join against media-svc was not run from this agent environment (needs a
minted guest/host token plus a physical or simulator camera entitlement).

## Token path (unchanged from the web studio)

1. Partner backend (`X-Api-Key`) calls `POST /streams/:id/studio/host-session`.
2. Response now includes `hostToken` / `guestToken` (plus the existing URLs).
3. iOS redeem: `POST /public/studio/host/:token` or `POST /public/studio/join/:token`.
4. media-svc returns `{ authToken, meetingId, role, studioControlToken?, stream }`.
5. `authToken` is a RealtimeKit participant JWT — same value the web SDK passes to
   `RealtimeKitClient.init`.

First-party ios-app uses `POST /streams/:id/studio/session` (org JWT only) and
injects the returned session into `StudioRoomView`.

## iOS Core API used by LivoStudioKit

```swift
let meeting = RealtimeKitiOSClientBuilder().build()
meeting.addMeetingRoomEventListener(meetingRoomEventListener: self)
meeting.addParticipantsEventListener(participantsEventListener: self)
meeting.addSelfEventListener(selfEventListener: self)
meeting.addWaitlistEventListener(self)

let info = RtkMeetingInfo(authToken: session.authToken, enableAudio: true, enableVideo: true)
meeting.doInit(meetingInfo: info, onSuccess: { meeting.joinRoom(...) }, onFailure: { _ in })

meeting.localUser.enableAudio { _ in }
meeting.localUser.disableAudio { _ in }
meeting.localUser.enableVideo { _ in }
meeting.localUser.disableVideo { _ in }
meeting.localUser.switchCamera()
let cameraView = meeting.localUser.getVideoView()
```

Waiting room (webinar presets `studio-moderator` / `studio-guest`):

- Guest: `onWaitListStatusUpdate` (`.waiting` / `.accepted` / `.rejected`)
- Host: `meeting.participants.waitlisted`, `acceptWaitingRoomRequest(id:)`,
  `rejectWaitingRoomRequest(_:)`

Host controls: `participant.kick()`, `participant.pin()` / `unpin()`.

Screen share (Phase 3): ReplayKit Broadcast Upload Extension +
`meeting.localUser.enableScreenShare()` — see `docs/SCREEN_SHARE.md`.

## Risk

`realtimekit-ios-core` has **no git tags**. `Package.swift` pins `branch: "main"`.
Re-check the XCFramework zip when bumping; checksums live in that repo's
`Package.swift`.
