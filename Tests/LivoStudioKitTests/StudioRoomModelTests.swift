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
    var stageLeft = false
    var cancelledStage = false
    var muted: [String] = []
    var camerasStopped: [String] = []
    var broadcasts: [(String, [String: String])] = []
    var audio: [StudioMediaDevice] = []
    var video: [StudioMediaDevice] = []

    func join(authToken: String, enableAudio: Bool, enableVideo: Bool) async throws {
        joined = true
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

    func setCameraEnabled(_ enabled: Bool) { camera = enabled }
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
    func joinStage() { stageJoined = true }
    func leaveStage() { stageLeft = true }
    func grantStage(id: String) { granted.append(id) }
    func denyStage(id: String) {}
    func takeOffStage(id: String) {}
    func muteRemoteAudio(id: String) { muted.append(id) }
    func disableRemoteVideo(id: String) { camerasStopped.append(id) }
    func sendBroadcast(type: String, payload: [String: String]) { broadcasts.append((type, payload)) }
    func audioDevices() -> [StudioMediaDevice] { audio }
    func videoDevices() -> [StudioMediaDevice] { video }
    func selectedAudioDeviceId() -> String? { audio.first?.id }
    func selectedVideoDeviceId() -> String? { video.first?.id }
    func setAudioDevice(id: String) {}
    func setVideoDevice(id: String) {}
    func videoView(for participantId: String, screenShare: Bool) -> UIView? { nil }
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
}
