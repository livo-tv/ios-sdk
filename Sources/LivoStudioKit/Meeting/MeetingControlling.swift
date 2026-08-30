import Foundation
import LivoStudioAPI
import UIKit

/// Abstraction over Cloudflare RealtimeKit so the SwiftUI room can be tested
/// without the binary XCFramework.
@MainActor
public protocol MeetingControlling: AnyObject {
    var delegate: MeetingControllerDelegate? { get set }

    func join(authToken: String, enableAudio: Bool, enableVideo: Bool) async throws
    func leave()
    func setCameraEnabled(_ enabled: Bool)
    func setMicrophoneEnabled(_ enabled: Bool)
    func switchCamera()
    func enableScreenShare()
    func disableScreenShare()
    func acceptWaitingRoom(id: String)
    func rejectWaitingRoom(id: String)
    func kick(id: String)
    func pin(id: String)
    func unpin(id: String)
    func sendChat(_ text: String)
    func requestStage()
    func cancelStageRequest()
    func joinStage()
    func leaveStage()
    func grantStage(id: String)
    func denyStage(id: String)
    func takeOffStage(id: String)
    func muteRemoteAudio(id: String)
    func disableRemoteVideo(id: String)
    func sendBroadcast(type: String, payload: [String: String])
    func audioDevices() -> [StudioMediaDevice]
    func videoDevices() -> [StudioMediaDevice]
    func selectedAudioDeviceId() -> String?
    func selectedVideoDeviceId() -> String?
    func setAudioDevice(id: String)
    func setVideoDevice(id: String)
    func videoView(for participantId: String, screenShare: Bool) -> UIView?
}

@MainActor
public protocol MeetingControllerDelegate: AnyObject {
    func meetingDidJoin()
    func meetingDidWaitlist()
    func meetingWasRejected()
    func meetingDidDisconnect(reason: MeetingDisconnectReason)
    func meetingDidUpdateParticipants(_ participants: [StudioParticipant])
    func meetingDidUpdateWaitlist(_ guests: [StudioWaitlistedGuest])
    func meetingDidReceiveChat(_ message: StudioChatMessage)
    func meetingDidUpdateStageRequests(_ requests: [StudioStageRequest])
    func meetingMediaDidChange(cameraOn: Bool, micOn: Bool, screenShareOn: Bool)
    func meetingDidUpdateActiveSpeaker(id: String?)
    func meetingSelfStageDidChange(_ status: StudioStageStatus?)
    func meetingDidReceiveBroadcast(_ message: StudioBroadcastMessage)
    func meetingDidUpdateDevices()
}

public enum MeetingDisconnectReason: Sendable, Equatable {
    case left
    case kicked
    case ended
    case failed(String)
}

public struct StudioMediaDevice: Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable, Hashable {
        case audio
        case video
    }

    public var id: String
    public var name: String
    public var kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public enum StudioBroadcastMessage: Equatable, Sendable {
    case hostMedia(kind: HostMediaKind)

    public enum HostMediaKind: String, Sendable {
        case audio
        case video
        case screen
    }
}

public enum MeetingControllerFactory {
    @MainActor
    public static func makeDefault() -> MeetingControlling {
        RealtimeKitMeetingController()
    }
}
