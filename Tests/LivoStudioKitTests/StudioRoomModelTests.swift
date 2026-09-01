import Foundation
import Testing
import UIKit
@testable import LivoStudioAPI
@testable import LivoStudioKit

@MainActor
final class MockMeetingController: MeetingControlling {
    weak var delegate: MeetingControllerDelegate?
    var joined = false
    var camera = true
    var mic = true
    var kicked: [String] = []
    var admitted: [String] = []
    var granted: [String] = []
    var rejected: [String] = []
    var chats: [String] = []
    var screenShare = false
    var stageJoined = false
    var joinStageCount = 0
    var stageLeft = false
    var takenOffStage: [String] = []
    var cancelledStage = false
    var muted: [String] = []
    var camerasStopped: [String] = []
    var broadcasts: [(String, [String: String])] = []
    var audio: [StudioMediaDevice] = []
    var video: [StudioMediaDevice] = []
    var videoViewRequests: [(String, Bool)] = []
    var signalingState: StudioSignalingState = .connected
    var joinCount = 0
    var cameraEnabledCalls: [Bool] = []

    func join(authToken: String, enableAudio: Bool, enableVideo: Bool) async throws {
        joined = true
        joinCount += 1
        camera = enableVideo
        mic = enableAudio
        delegate?.meetingDidJoin()
        delegate?.meetingDidUpdateParticipants([
            StudioParticipant(
                id: "self",
                name: "Host",
                isSelf: true,
                audioEnabled: mic,
                videoEnabled: camera
            ),
        ])
        delegate?.meetingMediaDidChange(cameraOn: camera, micOn: mic, screenShareOn: false)
    }

    func leave() {
        joined = false
        delegate?.meetingDidDisconnect(reason: .left)
    }

    func setCameraEnabled(_ enabled: Bool) {
        camera = enabled
        cameraEnabledCalls.append(enabled)
    }
    func setMicrophoneEnabled(_ enabled: Bool) { mic = enabled }
    func switchCamera() {}
    func enableScreenShare() { screenShare = true }
    func disableScreenShare() { screenShare = false }
    func acceptWaitingRoom(id: String) { admitted.append(id) }
    func rejectWaitingRoom(id: String) { rejected.append(id) }
    func acceptAllWaitingRoom(ids: [String]) { admitted.append(contentsOf: ids) }
    func kick(id: String) { kicked.append(id) }
    func pin(id: String) {}
    func unpin(id: String) {}
    func sendChat(_ text: String) { chats.append(text) }
    func requestStage() {}
    func cancelStageRequest() { cancelledStage = true }
    func joinStage() {
        stageJoined = true
        joinStageCount += 1
    }
    func leaveStage() { stageLeft = true }
    func grantStage(id: String) { granted.append(id) }
    func denyStage(id: String) {}
    func takeOffStage(id: String) { takenOffStage.append(id) }
    func muteRemoteAudio(id: String) { muted.append(id) }
    func disableRemoteVideo(id: String) { camerasStopped.append(id) }
    func sendBroadcast(type: String, payload: [String: String]) { broadcasts.append((type, payload)) }
    func audioDevices() -> [StudioMediaDevice] { audio }
    func videoDevices() -> [StudioMediaDevice] { video }
    func selectedAudioDeviceId() -> String? { audio.first?.id }
    func selectedVideoDeviceId() -> String? { video.first?.id }
    func setAudioDevice(id: String) {}
    func setVideoDevice(id: String) {}
    func videoView(for participantId: String, screenShare: Bool) -> UIView? {
        videoViewRequests.append((participantId, screenShare))
        return nil
    }
}

@MainActor
final class MockBackgroundTaskHolder: BackgroundTaskHolding {
    var began: [String] = []
    var ended: [UUID] = []

    func begin(_ name: String, expirationHandler: @escaping () -> Void) -> UUID {
        let id = UUID()
        began.append(name)
        return id
    }

    func end(_ id: UUID) {
        ended.append(id)
    }
}

struct StudioThemeTests {
    @Test func defaultThemeFollowsSystem() {
        #expect(StudioTheme.livo.mode == .system)
        #expect(StudioTheme.livo.radius == 12)
    }
}

@MainActor
struct StudioRoomModelTests {
    private func session(status: String = "preview") -> StudioSession {
        StudioSession(
            authToken: "rtk",
            meetingId: "mtg",
            role: .moderator,
            studioControlToken: nil,
            stream: StudioStreamSummary(id: "stm", title: "Show", status: status)
        )
    }

    @Test func startJoinsAndExposesSelfTile() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        #expect(model.phase == .inRoom)
        #expect(meeting.joined)
        #expect(model.participants.contains { $0.isSelf })
    }

    @Test func canPublishOnlyInPreview() async {
        let meeting = MockMeetingController()
        let preview = StudioRoomModel(session: session(status: "preview"), meeting: meeting)
        await preview.start()
        #expect(preview.canPublish)
        let live = StudioRoomModel(session: session(status: "public"), meeting: meeting)
        await live.start()
        #expect(!live.canPublish)
        #expect(live.isLive)
    }

    @Test func leaveEmitsLeft() async {
        let meeting = MockMeetingController()
        var events: [StudioEvent] = []
        let model = StudioRoomModel(session: session(), meeting: meeting) { events.append($0) }
        await model.start()
        model.leave()
        #expect(model.phase == .left)
        #expect(events.contains { if case .left = $0 { return true }; return false })
    }

    @Test func admitAndChatForwardToMeeting() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.admit(StudioWaitlistedGuest(id: "g1", name: "Pat"))
        model.sendChat("hello")
        model.kick(StudioParticipant(id: "p2", name: "Bo", isSelf: false, audioEnabled: true, videoEnabled: true))
        #expect(meeting.admitted == ["g1"])
        #expect(meeting.chats == ["hello"])
        #expect(meeting.kicked == ["p2"])
    }

    @Test func identicalParticipantSnapshotsDoNotReplaceList() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        let snapshot = model.participants
        model.meetingDidUpdateParticipants(snapshot)
        #expect(model.participants == snapshot)
        model.meetingDidUpdateParticipants([
            StudioParticipant(id: "self", name: "Host", isSelf: true, audioEnabled: true, videoEnabled: false),
        ])
        #expect(model.participants.first?.videoEnabled == false)
    }

    @Test func dismissRoomOnLeftReemitsLeft() async {
        let meeting = MockMeetingController()
        var events: [StudioEvent] = []
        let model = StudioRoomModel(session: session(), meeting: meeting) { events.append($0) }
        await model.start()
        model.leave()
        events.removeAll()
        model.dismissRoom()
        #expect(events.contains { if case .left = $0 { return true }; return false })
        #expect(model.phase == .left)
    }

    @Test func stageFilterHidesAudience() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.meetingDidUpdateParticipants([
            StudioParticipant(id: "self", name: "Host", isSelf: true, audioEnabled: true, videoEnabled: true, stageStatus: .onStage),
            StudioParticipant(id: "aud", name: "Pat", isSelf: false, audioEnabled: true, videoEnabled: true, stageStatus: .offStage),
        ])
        #expect(model.stageParticipants.map(\.id) == ["self"])
        #expect(model.audienceParticipants.map(\.id) == ["aud"])
    }

    @Test func lastVisibleBlockedWhenLive() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(status: "public"), meeting: meeting)
        await model.start()
        model.meetingDidUpdateParticipants([
            StudioParticipant(id: "self", name: "Host", isSelf: true, audioEnabled: true, videoEnabled: true, stageStatus: .onStage),
        ])
        #expect(model.isLive)
        #expect(!model.canTakeOffAir(model.selfParticipant))
        model.takeOffStage(model.selfParticipant!)
        #expect(model.toasts.isEmpty == false)
    }

    @Test func waitlistKnockPushesToastAfterPrime() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.meetingDidUpdateWaitlist([StudioWaitlistedGuest(id: "g1", name: "Pat")])
        #expect(model.toasts.isEmpty)
        model.meetingDidUpdateWaitlist([
            StudioWaitlistedGuest(id: "g1", name: "Pat"),
            StudioWaitlistedGuest(id: "g2", name: "Sam"),
        ])
        #expect(model.toasts.contains { $0.message.contains("Sam") })
    }

    @Test func guestStageDeniedToasts() async {
        let meeting = MockMeetingController()
        let guest = StudioSession(
            authToken: "rtk",
            meetingId: "mtg",
            role: .guest,
            stream: StudioStreamSummary(id: "stm", title: "Show", status: "preview")
        )
        let model = StudioRoomModel(session: guest, meeting: meeting)
        await model.start()
        model.meetingSelfStageDidChange(.requestedToJoinStage)
        model.meetingSelfStageDidChange(.offStage)
        #expect(model.toasts.contains { $0.message.contains("denied") })
    }

    @Test func muteConfirmBroadcastsHostMedia() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        let guest = StudioParticipant(id: "p2", name: "Bo", isSelf: false, audioEnabled: true, videoEnabled: true)
        model.pendingConfirm = .mute(guest)
        model.confirmMute()
        #expect(meeting.muted == ["p2"])
        #expect(meeting.broadcasts.first?.0 == "host-media")
    }

    @Test func admitAsPanelistQueuesGrantWhenAlreadyJoined() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.meetingDidUpdateParticipants([
            StudioParticipant(id: "self", name: "Host", isSelf: true, audioEnabled: true, videoEnabled: true),
            StudioParticipant(id: "g1", name: "Pat", isSelf: false, audioEnabled: true, videoEnabled: true, userId: "u1", stageStatus: .offStage),
        ])
        model.admit(StudioWaitlistedGuest(id: "g1", name: "Pat", userId: "u1"), as: .panelist)
        #expect(meeting.admitted == ["g1"])
        #expect(meeting.granted.contains("u1"))
    }

    @Test func admitAllAsPanelistsGrantsEach() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.meetingDidUpdateWaitlist([
            StudioWaitlistedGuest(id: "g1", name: "Pat", userId: "u1"),
            StudioWaitlistedGuest(id: "g2", name: "Sam", userId: "u2"),
        ])
        model.meetingDidUpdateParticipants([
            StudioParticipant(id: "self", name: "Host", isSelf: true, audioEnabled: true, videoEnabled: true),
            StudioParticipant(id: "g1", name: "Pat", isSelf: false, audioEnabled: true, videoEnabled: true, userId: "u1"),
            StudioParticipant(id: "g2", name: "Sam", isSelf: false, audioEnabled: true, videoEnabled: true, userId: "u2"),
        ])
        model.admitAll(as: .panelist)
        #expect(meeting.admitted == ["g1", "g2"])
        #expect(meeting.granted.contains("u1"))
        #expect(meeting.granted.contains("u2"))
    }

    @Test func admitAsAudienceDoesNotGrantStage() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.admit(StudioWaitlistedGuest(id: "g1", name: "Pat", userId: "u1"), as: .audience)
        #expect(meeting.admitted == ["g1"])
        #expect(meeting.granted.isEmpty)
    }

    @Test func stopScreenBroadcastsHostMedia() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        let guest = StudioParticipant(id: "p2", name: "Bo", isSelf: false, audioEnabled: true, videoEnabled: true, userId: "u2")
        model.pendingConfirm = .stopScreen(guest)
        model.confirmStopScreen()
        #expect(meeting.broadcasts.contains { $0.0 == "host-media" && $0.1["kind"] == "screen" && $0.1["userId"] == "u2" })
    }

    @Test func hostMediaScreenDisablesLocalShare() async {
        let meeting = MockMeetingController()
        let guest = StudioSession(
            authToken: "rtk",
            meetingId: "mtg",
            role: .guest,
            stream: StudioStreamSummary(id: "stm", title: "Show", status: "preview")
        )
        let model = StudioRoomModel(session: guest, meeting: meeting)
        await model.start()
        meeting.screenShare = true
        model.meetingDidReceiveBroadcast(.hostMedia(kind: .screen, targetUserId: "self"))
        #expect(meeting.screenShare == false)
        #expect(model.toasts.contains { $0.message.contains("screen") })
    }

    @Test func screenShareFailureRollsBack() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.meetingDidFailScreenShare(reason: "No broadcast extension")
        #expect(!model.screenShareOn)
        #expect(model.toasts.contains { $0.message.contains("broadcast") })
    }

    @Test func hostTileHintShowsOnce() async {
        let defaults = UserDefaults(suiteName: "livo.studio.tests.\(UUID().uuidString)")!
        defaults.removeObject(forKey: StudioRoomModel.hostTileHintKey)
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting, defaults: defaults)
        await model.start()
        #expect(model.toasts.contains { $0.message.contains("long-press") })
        let again = StudioRoomModel(session: session(), meeting: MockMeetingController(), defaults: defaults)
        await again.start()
        #expect(!again.toasts.contains { $0.message.contains("long-press") })
    }

    @Test func idleTileDoesNotRequestCameraView() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        let guest = StudioParticipant(
            id: "g1",
            name: "Pat",
            isSelf: false,
            audioEnabled: true,
            videoEnabled: false
        )
        let idle = StudioDisplayTile(tileId: "g1:idle", kind: .idle, participant: guest)
        let before = meeting.videoViewRequests.count
        #expect(model.videoView(for: idle) == nil)
        #expect(meeting.videoViewRequests.count == before)
    }

    @Test func toggleSideTabClosesAndReopens() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        #expect(model.selectedTab == nil)
        model.toggleSideTab(.people)
        #expect(model.selectedTab == .people)
        model.toggleSideTab(.people)
        #expect(model.selectedTab == nil)
        model.toggleSideTab(.chat)
        #expect(model.selectedTab == .chat)
        model.toggleSideTab(.chat)
        #expect(model.selectedTab == nil)
        model.toggleSideTab(.people)
        #expect(model.selectedTab == .people)
    }

    @Test func knockWhileHiddenOpensPeople() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.meetingDidUpdateWaitlist([StudioWaitlistedGuest(id: "g1", name: "Pat")])
        model.toggleSideTab(.people)
        #expect(model.selectedTab == nil)
        model.meetingDidUpdateWaitlist([
            StudioWaitlistedGuest(id: "g1", name: "Pat"),
            StudioWaitlistedGuest(id: "g2", name: "Sam"),
        ])
        #expect(model.selectedTab == .people)
    }

    @Test func openingChatClearsUnread() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.meetingDidReceiveChat(
            StudioChatMessage(id: "m1", userId: "p2", name: "Bo", text: "hi", time: 0)
        )
        #expect(model.unreadChat == 1)
        model.toggleSideTab(.chat)
        #expect(model.unreadChat == 0)
        #expect(model.selectedTab == .chat)
    }

    @Test func socketFailedLeavesInRoom() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        #expect(model.phase == .inRoom)
        model.meetingDidDisconnect(reason: .failed("Connection lost. Leave and rejoin."))
        guard case let .failed(message) = model.phase else {
            Issue.record("expected failed phase, got \(model.phase)")
            return
        }
        #expect(message.contains("rejoin"))
        #expect(model.phase != .inRoom)
    }

    @Test func socketFailedDoesNotOverrideLeft() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.leave()
        model.meetingDidDisconnect(reason: .failed("Connection lost. Leave and rejoin."))
        #expect(model.phase == .left)
    }

    @Test func cameraTileRequestsRenderer() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        let guest = StudioParticipant(
            id: "g1",
            name: "Pat",
            isSelf: false,
            audioEnabled: true,
            videoEnabled: true
        )
        let camera = StudioDisplayTile(tileId: "g1:camera", kind: .camera, participant: guest)
        _ = model.videoView(for: camera)
        #expect(meeting.videoViewRequests.contains { $0.0 == "g1" && $0.1 == false })
    }

    @Test func pauseOutgoingCameraKeepsIntentAndResumeCycles() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        meeting.cameraEnabledCalls.removeAll()
        #expect(model.cameraOn)
        model.pauseOutgoingCamera()
        #expect(model.cameraOn)
        #expect(meeting.cameraEnabledCalls == [false])
        model.meetingMediaDidChange(cameraOn: false, micOn: true, screenShareOn: false)
        #expect(model.cameraOn)
        meeting.cameraEnabledCalls.removeAll()
        model.resumeOutgoingCamera()
        #expect(model.cameraOn)
        #expect(meeting.cameraEnabledCalls == [false, true])
    }

    @Test func pauseWhileCameraOffIsNoOp() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.toggleCamera()
        meeting.cameraEnabledCalls.removeAll()
        model.pauseOutgoingCamera()
        #expect(meeting.cameraEnabledCalls.isEmpty)
        #expect(!model.cameraOn)
    }

    @Test func reconnectAfterFailedReturnsToRoom() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        #expect(meeting.joinCount == 1)
        model.meetingDidDisconnect(reason: .failed("Connection lost. Leave and rejoin."))
        guard case .failed = model.phase else {
            Issue.record("expected failed phase, got \(model.phase)")
            return
        }
        await model.reconnect()
        #expect(model.phase == .inRoom)
        #expect(meeting.joinCount == 2)
        #expect(meeting.joined)
    }

    @Test func foregroundWithoutBackgroundDoesNotRejoin() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        meeting.signalingState = .failed
        await model.handleSceneBecameActive()
        #expect(meeting.joinCount == 1)
    }

    @Test func backgroundTaskBeginsAndEnds() async {
        let meeting = MockMeetingController()
        let tasks = MockBackgroundTaskHolder()
        let model = StudioRoomModel(session: session(), meeting: meeting, backgroundTasks: tasks)
        await model.start()
        model.handleSceneBackgrounded()
        #expect(tasks.began == ["livo.studio"])
        await model.handleSceneBecameActive()
        #expect(tasks.ended.count == 1)
        #expect(meeting.joinCount == 1)
    }

    @Test func reconnectingThatHealsDoesNotRebuild() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(
            session: session(),
            apiURL: URL(string: "http://127.0.0.1:9")!,
            meeting: meeting
        )
        await model.start()
        model.signalingGraceInterval = .milliseconds(20)
        model.signalingGraceAttempts = 8
        meeting.signalingState = .reconnecting
        model.handleSceneBackgrounded()
        let recover = Task { await model.handleSceneBecameActive() }
        try? await Task.sleep(for: .milliseconds(40))
        meeting.signalingState = .connected
        await recover.value
        #expect(meeting.joinCount == 1)
        #expect(model.phase == .inRoom)
        model.tearDown()
    }

    @Test func failedAfterBackgroundRejoinsOnce() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        meeting.signalingState = .failed
        model.handleSceneBackgrounded()
        await model.handleSceneBecameActive()
        #expect(meeting.joinCount == 2)
        #expect(model.phase == .inRoom)
        #expect(model.toasts.contains { $0.message.contains("Reconnecting") })
    }

    @Test func nilRendererRetriesThenStops() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.rendererRetryDelay = .milliseconds(40)
        model.rendererRetryLimit = 3
        let guest = StudioParticipant(
            id: "g1",
            name: "Pat",
            isSelf: false,
            audioEnabled: true,
            videoEnabled: true,
            stageStatus: .onStage
        )
        model.meetingDidUpdateParticipants([
            StudioParticipant(
                id: "self",
                name: "Host",
                isSelf: true,
                audioEnabled: true,
                videoEnabled: true,
                stageStatus: .onStage
            ),
            guest,
        ])
        try? await Task.sleep(for: .milliseconds(140))
        #expect(meeting.videoViewRequests.count >= 2)
        model.tearDown()
        let after = meeting.videoViewRequests.count
        try? await Task.sleep(for: .milliseconds(80))
        #expect(meeting.videoViewRequests.count == after)
    }

    @Test func guestAcceptedJoinsStageAndUnlocksMedia() async {
        let meeting = MockMeetingController()
        let guest = StudioSession(
            authToken: "rtk",
            meetingId: "mtg",
            role: .guest,
            stream: StudioStreamSummary(id: "stm", title: "Show", status: "preview")
        )
        let model = StudioRoomModel(session: guest, meeting: meeting)
        await model.start()
        model.meetingSelfStageDidChange(.offStage)
        #expect(!model.canUseMediaControls)
        model.meetingSelfStageDidChange(.acceptedToJoinStage)
        #expect(meeting.stageJoined)
        model.meetingSelfStageDidChange(.onStage)
        #expect(model.canUseMediaControls)
    }

    @Test func emptyUserIdGrantsPeerId() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        model.meetingDidUpdateParticipants([
            StudioParticipant(
                id: "self",
                name: "Host",
                isSelf: true,
                audioEnabled: true,
                videoEnabled: true
            ),
            StudioParticipant(
                id: "g1",
                name: "Pat",
                isSelf: false,
                audioEnabled: true,
                videoEnabled: true,
                userId: "",
                stageStatus: .offStage
            ),
        ])
        model.admit(StudioWaitlistedGuest(id: "g1", name: "Pat", userId: ""), as: .panelist)
        #expect(meeting.admitted == ["g1"])
        #expect(meeting.granted.contains("g1"))
        #expect(!meeting.granted.contains(""))
    }

    @Test func bringOnAirAndTakeOffUseStageId() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        let guest = StudioParticipant(
            id: "g1",
            name: "Pat",
            isSelf: false,
            audioEnabled: true,
            videoEnabled: true,
            userId: ""
        )
        model.bringOnAir(guest)
        #expect(meeting.granted == ["g1"])
        model.takeOffStage(guest)
        #expect(meeting.takenOffStage == ["g1"])
    }

    @Test func grantBeforeRoomJoinFlushesOnDidJoin() async {
        let meeting = MockMeetingController()
        let guest = StudioSession(
            authToken: "rtk",
            meetingId: "mtg",
            role: .guest,
            stream: StudioStreamSummary(id: "stm", title: "Show", status: "preview")
        )
        let model = StudioRoomModel(session: guest, meeting: meeting)
        model.meetingSelfStageDidChange(.acceptedToJoinStage)
        #expect(meeting.joinStageCount == 1)
        model.meetingDidJoin()
        #expect(meeting.joinStageCount == 2)
        #expect(model.phase == .inRoom)
        model.tearDown()
    }

    @Test func joinStageWatchdogRetriesWhileAccepted() async {
        let meeting = MockMeetingController()
        let guest = StudioSession(
            authToken: "rtk",
            meetingId: "mtg",
            role: .guest,
            stream: StudioStreamSummary(id: "stm", title: "Show", status: "preview")
        )
        let model = StudioRoomModel(session: guest, meeting: meeting)
        await model.start()
        model.meetingSelfStageDidChange(.acceptedToJoinStage)
        #expect(meeting.joinStageCount == 1)
        try? await Task.sleep(for: .milliseconds(1800))
        #expect(meeting.joinStageCount >= 2)
        model.meetingSelfStageDidChange(.onStage)
        let after = meeting.joinStageCount
        try? await Task.sleep(for: .milliseconds(1800))
        #expect(meeting.joinStageCount == after)
        model.tearDown()
    }

    @Test func closePanelClearsSelectedTab() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        #expect(model.selectedTab == nil)
        model.toggleSideTab(.people)
        #expect(model.selectedTab == .people)
        model.selectedTab = nil
        #expect(model.selectedTab == nil)
        model.toggleSideTab(.chat)
        #expect(model.selectedTab == .chat)
        model.toggleSideTab(.chat)
        #expect(model.selectedTab == nil)
    }

    @Test func cameraTileWithoutRendererIsNil() async {
        let meeting = MockMeetingController()
        let model = StudioRoomModel(session: session(), meeting: meeting)
        await model.start()
        let guest = StudioParticipant(
            id: "g1",
            name: "Pat",
            isSelf: false,
            audioEnabled: true,
            videoEnabled: true
        )
        let camera = StudioDisplayTile(tileId: "g1:camera", kind: .camera, participant: guest)
        #expect(model.videoView(for: camera) == nil)
    }
}
