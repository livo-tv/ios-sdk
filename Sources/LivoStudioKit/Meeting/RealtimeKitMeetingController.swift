import Foundation
import LivoStudioAPI
import RealtimeKit
import UIKit

/// Cloudflare RealtimeKit Core adapter. Signatures match the 3.1.0 ObjC/Swift header.
@MainActor
public final class RealtimeKitMeetingController: NSObject, MeetingControlling {
    public weak var delegate: MeetingControllerDelegate?

    private var meeting: RealtimeKitClient?
    private var joining = false
    /// `getVideoView()` can allocate a new renderer. Reusing the first instance
    /// keeps the local camera from blinking on periodic RTK / SwiftUI updates.
    private var videoViews: [String: UIView] = [:]

    override public init() {
        super.init()
    }

    public func join(authToken: String, enableAudio: Bool, enableVideo: Bool) async throws {
        if joining { return }
        joining = true
        let client = RealtimeKitiOSClientBuilder().build()
        meeting = client
        client.addMeetingRoomEventListener(meetingRoomEventListener: self)
        client.addParticipantsEventListener(participantsEventListener: self)
        client.addSelfEventListener(selfEventListener: self)
        client.addWaitlistEventListener(waitlistEventListener: self)
        client.addChatEventListener(chatEventListener: self)
        client.addStageEventListener(stageEventListener: self)

        let info = RtkMeetingInfo(authToken: authToken, enableAudio: enableAudio, enableVideo: enableVideo)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            func finish(_ error: Error?) {
                guard !resumed else { return }
                resumed = true
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            client.doInit(meetingInfo: info, onSuccess: {
                client.joinRoom(onSuccess: {
                    finish(nil)
                }, onFailure: { error in
                    finish(StudioAPIError(status: 502, message: error.message))
                })
            }, onFailure: { error in
                finish(StudioAPIError(status: 502, message: error.message))
            })
        }
        publishParticipants()
        publishWaitlist()
        publishMedia()
        publishSelfStage()
        publishDevices()
    }

    public func leave() {
        meeting?.leaveRoom(onSuccess: {}, onFailure: { _ in })
        joining = false
        videoViews.removeAll()
    }

    public func setCameraEnabled(_ enabled: Bool) {
        if enabled {
            meeting?.localUser.enableVideo(onResult: { _ in Task { @MainActor in self.publishMedia() } })
        } else {
            meeting?.localUser.disableVideo(onResult: { _ in Task { @MainActor in self.publishMedia() } })
        }
    }

    public func setMicrophoneEnabled(_ enabled: Bool) {
        if enabled {
            meeting?.localUser.enableAudio(onResult: { _ in Task { @MainActor in self.publishMedia() } })
        } else {
            meeting?.localUser.disableAudio(onResult: { _ in Task { @MainActor in self.publishMedia() } })
        }
    }

    public func switchCamera() {
        meeting?.localUser.switchCamera()
    }

    public func enableScreenShare() {
        meeting?.localUser.enableScreenShare(onResult: { _ in Task { @MainActor in self.publishMedia() } })
    }

    public func disableScreenShare() {
        meeting?.localUser.disableScreenShare(onResult: { _ in Task { @MainActor in self.publishMedia() } })
    }

    public func acceptWaitingRoom(id: String) {
        meeting?.participants.acceptWaitingRoomRequest(id: id)
    }

    public func rejectWaitingRoom(id: String) {
        meeting?.participants.rejectWaitingRoomRequest(id: id)
    }

    public func acceptAllWaitingRoom(ids: [String]) {
        for id in ids {
            meeting?.participants.acceptWaitingRoomRequest(id: id)
        }
    }

    public func kick(id: String) {
        _ = remote(id)?.kick()
    }

    public func pin(id: String) {
        _ = remote(id)?.pin()
    }

    public func unpin(id: String) {
        _ = remote(id)?.unpin()
    }

    public func sendChat(_ text: String) {
        _ = meeting?.chat.sendTextMessage(message: text)
    }

    public func requestStage() {
        _ = meeting?.stage.requestAccess()
    }

    public func cancelStageRequest() {
        _ = meeting?.stage.cancelRequestAccess()
    }

    public func joinStage() {
        _ = meeting?.stage.join()
        publishSelfStage()
    }

    public func leaveStage() {
        _ = meeting?.stage.leave()
        publishSelfStage()
    }

    public func grantStage(id: String) {
        _ = meeting?.stage.grantAccess(userIds: [id])
    }

    public func denyStage(id: String) {
        _ = meeting?.stage.denyAccess(userIds: [id])
    }

    public func takeOffStage(id: String) {
        _ = meeting?.stage.kick(userIds: [id])
    }

    public func muteRemoteAudio(id: String) {
        _ = remote(id)?.disableAudio()
    }

    public func disableRemoteVideo(id: String) {
        _ = remote(id)?.disableVideo()
    }

    public func sendBroadcast(type: String, payload: [String: String]) {
        meeting?.participants.broadcastMessage(type: type, payload: payload)
    }

    public func audioDevices() -> [StudioMediaDevice] {
        (meeting?.localUser.getAudioDevices() ?? []).map { device in
            StudioMediaDevice(id: device.id, name: device.type.displayName, kind: .audio)
        }
    }

    public func videoDevices() -> [StudioMediaDevice] {
        (meeting?.localUser.getVideoDevices() ?? []).map { device in
            StudioMediaDevice(id: device.id, name: device.description, kind: .video)
        }
    }

    public func selectedAudioDeviceId() -> String? {
        meeting?.localUser.getSelectedAudioDevice()?.id
    }

    public func selectedVideoDeviceId() -> String? {
        meeting?.localUser.getSelectedVideoDevice()?.id
    }

    public func setAudioDevice(id: String) {
        guard let device = meeting?.localUser.getAudioDevices().first(where: { $0.id == id }) else { return }
        meeting?.localUser.setAudioDevice(rtkAudioDevice: device)
    }

    public func setVideoDevice(id: String) {
        guard let device = meeting?.localUser.getVideoDevices().first(where: { $0.id == id }) else { return }
        meeting?.localUser.setVideoDevice(rtkVideoDevice: device)
    }

    public func videoView(for participantId: String, screenShare: Bool) -> UIView? {
        let key = Self.videoViewKey(participantId: participantId, screenShare: screenShare)
        if let cached = videoViews[key] { return cached }
        guard let meeting else { return nil }
        let view: UIView?
        if meeting.localUser.id == participantId {
            view = screenShare ? meeting.localUser.getScreenShareVideoView() : meeting.localUser.getVideoView()
        } else if let participant = remote(participantId) {
            view = screenShare ? participant.getScreenShareVideoView() : participant.getVideoView()
        } else {
            view = nil
        }
        if let view {
            videoViews[key] = view
        }
        return view
    }

    fileprivate static func videoViewKey(participantId: String, screenShare: Bool) -> String {
        screenShare ? "\(participantId)#screen" : participantId
    }

    private func remote(_ id: String) -> RtkRemoteParticipant? {
        meeting?.participants.joined.first { $0.id == id }
    }

    fileprivate func publishMedia() {
        guard let user = meeting?.localUser else { return }
        delegate?.meetingMediaDidChange(
            cameraOn: user.videoEnabled,
            micOn: user.audioEnabled,
            screenShareOn: user.screenShareEnabled
        )
    }

    fileprivate func publishSelfStage() {
        let status = meeting?.stage.stageStatus ?? meeting?.localUser.stageStatus
        delegate?.meetingSelfStageDidChange(mapStage(status))
    }

    fileprivate func publishDevices() {
        delegate?.meetingDidUpdateDevices()
    }

    fileprivate static func parseBroadcast(type: String, payload: [String: Any]) -> StudioBroadcastMessage? {
        let nested = payload["payload"] as? [String: Any]
        let body = nested ?? payload
        let resolvedType = (body["type"] as? String) ?? type
        guard resolvedType == "host-media" else { return nil }
        let kind = (body["kind"] as? String).flatMap(StudioBroadcastMessage.HostMediaKind.init(rawValue:))
        guard let kind else { return nil }
        let target = (body["userId"] as? String) ?? (body["targetUserId"] as? String)
        return .hostMedia(kind: kind, targetUserId: target)
    }

    fileprivate func publishParticipants() {
        guard let meeting else { return }
        var tiles: [StudioParticipant] = []
        let selfUser = meeting.localUser
        tiles.append(tile(id: selfUser.id, name: selfUser.name, isSelf: true, audio: selfUser.audioEnabled, video: selfUser.videoEnabled, screen: selfUser.screenShareEnabled, picture: selfUser.picture, userId: selfUser.userId, pinned: selfUser.isPinned, stage: selfUser.stageStatus))
        for participant in meeting.participants.joined {
            tiles.append(tile(id: participant.id, name: participant.name, isSelf: false, audio: participant.audioEnabled, video: participant.videoEnabled, screen: participant.screenShareEnabled, picture: participant.picture, userId: participant.userId, pinned: participant.isPinned, stage: participant.stageStatus))
        }
        delegate?.meetingDidUpdateParticipants(tiles)
    }

    fileprivate func publishWaitlist() {
        let guests = (meeting?.participants.waitlisted ?? []).map {
            StudioWaitlistedGuest(id: $0.id, name: $0.name, userId: $0.userId, picture: $0.picture)
        }
        delegate?.meetingDidUpdateWaitlist(guests)
    }

    fileprivate func publishStageRequests() {
        // Access requests arrive via RtkStageEventListener.
    }

    private func tile(
        id: String,
        name: String?,
        isSelf: Bool,
        audio: Bool,
        video: Bool,
        screen: Bool,
        picture: String?,
        userId: String?,
        pinned: Bool,
        stage: StageStatus?
    ) -> StudioParticipant {
        StudioParticipant(
            id: id,
            name: name ?? (isSelf ? "You" : "Guest"),
            isSelf: isSelf,
            audioEnabled: audio,
            videoEnabled: video,
            screenShareEnabled: screen,
            picture: picture,
            userId: userId,
            stageStatus: mapStage(stage),
            pinned: pinned
        )
    }

    private func mapStage(_ status: StageStatus?) -> StudioStageStatus? {
        guard let status else { return nil }
        switch status {
        case .offStage: return .offStage
        case .requestedToJoinStage: return .requestedToJoinStage
        case .acceptedToJoinStage: return .acceptedToJoinStage
        case .onStage: return .onStage
        @unknown default: return nil
        }
    }
}

extension RealtimeKitMeetingController: @preconcurrency RtkMeetingRoomEventListener {
    public func onActiveTabUpdate(meeting: RealtimeKitClient, activeTab: ActiveTab) {}
    public func onMeetingInitCompleted(meeting: RealtimeKitClient) {}
    public func onMeetingInitFailed(error: MeetingError) {}
    public func onMeetingInitStarted() {}
    public func onMeetingRoomJoinStarted() {}
    public func onMeetingRoomJoinFailed(error: MeetingError) {}
    public func onMeetingRoomLeaveStarted() {}
    public func onMeetingRoomLeaveCompleted() {}
    public func onMediaConnectionUpdate(update: MediaConnectionUpdate) {}
    public func onSocketConnectionUpdate(newState: SocketConnectionState) {}

    public func onMeetingRoomJoinCompleted(meeting: RealtimeKitClient) {
        Task { @MainActor in
            self.delegate?.meetingDidJoin()
            self.publishParticipants()
        }
    }

    public func onMeetingEnded() {
        Task { @MainActor in
            self.delegate?.meetingDidDisconnect(reason: .ended)
        }
    }
}

extension RealtimeKitMeetingController: @preconcurrency RtkParticipantsEventListener {
    public func onActiveParticipantsChanged(active: [RtkRemoteParticipant]) {}
    public func onActiveSpeakerChanged(participant: RtkRemoteParticipant?) {
        Task { @MainActor in
            self.delegate?.meetingDidUpdateActiveSpeaker(id: participant?.id)
        }
    }
    public func onAllParticipantsUpdated(allParticipants: [RtkParticipant]) {}
    public func onNewBroadcastMessage(type: String, payload: [String: Any]) {
        Task { @MainActor in
            if let message = Self.parseBroadcast(type: type, payload: payload) {
                self.delegate?.meetingDidReceiveBroadcast(message)
            }
        }
    }
    public func onScreenShareUpdate(participant: RtkRemoteParticipant, isEnabled: Bool) {
        Task { @MainActor in self.publishParticipants() }
    }

    public func onUpdate(participants: RtkParticipants) {
        Task { @MainActor in
            self.publishParticipants()
            self.publishWaitlist()
        }
    }

    public func onParticipantJoin(participant: RtkRemoteParticipant) {
        Task { @MainActor in self.publishParticipants() }
    }

    public func onParticipantLeave(participant: RtkRemoteParticipant) {
        Task { @MainActor in
            self.videoViews.removeValue(
                forKey: Self.videoViewKey(participantId: participant.id, screenShare: false)
            )
            self.videoViews.removeValue(
                forKey: Self.videoViewKey(participantId: participant.id, screenShare: true)
            )
            self.publishParticipants()
        }
    }

    public func onAudioUpdate(participant: RtkRemoteParticipant, isEnabled: Bool) {
        Task { @MainActor in self.publishParticipants() }
    }

    public func onVideoUpdate(participant: RtkRemoteParticipant, isEnabled: Bool) {
        Task { @MainActor in self.publishParticipants() }
    }

    public func onParticipantPinned(participant: RtkRemoteParticipant) {
        Task { @MainActor in self.publishParticipants() }
    }

    public func onParticipantUnpinned(participant: RtkRemoteParticipant) {
        Task { @MainActor in self.publishParticipants() }
    }
}

extension RealtimeKitMeetingController: @preconcurrency RtkSelfEventListener {
    public func onAudioDeviceChanged(audioDevice: AudioDevice) {
        Task { @MainActor in self.publishDevices() }
    }

    public func onAudioDevicesUpdated(devices: [AudioDevice]) {
        Task { @MainActor in self.publishDevices() }
    }
    public func onMeetingRoomJoinedWithoutCameraPermission() {}
    public func onMeetingRoomJoinedWithoutMicPermission() {}
    public func onPermissionsUpdated(permission: SelfPermissions) {}
    public func onPinned() {}
    public func onUnpinned() {}
    public func onScreenShareStartFailed(reason: String) {
        Task { @MainActor in
            self.publishMedia()
            self.delegate?.meetingDidFailScreenShare(reason: reason)
        }
    }
    public func onUpdate(participant: RtkSelfParticipant) {
        Task { @MainActor in
            self.publishMedia()
            self.publishParticipants()
        }
    }

    public func onVideoDeviceChanged(videoDevice: VideoDevice) {
        Task { @MainActor in self.publishDevices() }
    }

    public func onVideoUpdate(isEnabled: Bool) {
        Task { @MainActor in
            self.publishMedia()
            self.publishParticipants()
        }
    }

    public func onAudioUpdate(isEnabled: Bool) {
        Task { @MainActor in
            self.publishMedia()
            self.publishParticipants()
        }
    }

    public func onScreenShareUpdate(isEnabled: Bool) {
        Task { @MainActor in self.publishMedia() }
    }

    public func onRemovedFromMeeting() {
        Task { @MainActor in
            self.delegate?.meetingDidDisconnect(reason: .kicked)
        }
    }

    public func onWaitListStatusUpdate(waitListStatus: WaitListStatus) {
        Task { @MainActor in
            if waitListStatus == .waiting {
                self.delegate?.meetingDidWaitlist()
            } else if waitListStatus == .rejected {
                self.delegate?.meetingWasRejected()
            } else if waitListStatus == .accepted {
                self.delegate?.meetingDidJoin()
            }
        }
    }
}

extension RealtimeKitMeetingController: @preconcurrency RtkWaitlistEventListener {
    public func onWaitListParticipantJoined(participant: RtkRemoteParticipant) {
        Task { @MainActor in self.publishWaitlist() }
    }

    public func onWaitListParticipantAccepted(participant: RtkRemoteParticipant) {
        Task { @MainActor in
            self.publishWaitlist()
            self.publishParticipants()
        }
    }

    public func onWaitListParticipantRejected(participant: RtkRemoteParticipant) {
        Task { @MainActor in self.publishWaitlist() }
    }

    public func onWaitListParticipantClosed(participant: RtkRemoteParticipant) {
        Task { @MainActor in self.publishWaitlist() }
    }
}

extension RealtimeKitMeetingController: @preconcurrency RtkChatEventListener {
    public func onChatUpdates(messages: [ChatMessage]) {}
    public func onMessageDeleted(messageId: String) {}
    public func onMessageEdited(message: ChatMessage) {}
    public func onMessageRateLimitReset() {}

    public func onNewChatMessage(message: ChatMessage) {
        let text = (message as? TextMessage)?.message ?? ""
        let mapped = StudioChatMessage(
            id: message.id,
            userId: message.userId,
            name: message.displayName,
            text: text,
            time: TimeInterval(message.createdAtMillis) / 1000,
            targetUserIds: message.targetUserIds ?? [],
            pinned: message.pinned,
            isEdited: message.isEdited
        )
        Task { @MainActor in
            self.delegate?.meetingDidReceiveChat(mapped)
        }
    }
}

extension RealtimeKitMeetingController: @preconcurrency RtkStageEventListener {
    public func onNewStageAccessRequest(participant: RtkRemoteParticipant) {
        Task { @MainActor in self.publishStage(from: [participant]) }
    }

    public func onPeerStageStatusUpdated(participant: RtkRemoteParticipant, oldStatus: StageStatus, newStatus: StageStatus) {
        Task { @MainActor in self.publishParticipants() }
    }

    public func onRemovedFromStage() {
        Task { @MainActor in
            self.publishSelfStage()
            self.publishParticipants()
        }
    }

    public func onStageAccessRequestAccepted() {
        Task { @MainActor in
            _ = self.meeting?.stage.join()
            self.publishSelfStage()
        }
    }

    public func onStageAccessRequestRejected() {
        Task { @MainActor in self.publishSelfStage() }
    }

    public func onStageAccessRequestsUpdated(accessRequests: [RtkRemoteParticipant]) {
        Task { @MainActor in self.publishStage(from: accessRequests) }
    }

    public func onStageStatusUpdated(oldStatus: StageStatus, newStatus: StageStatus) {
        Task { @MainActor in
            self.publishSelfStage()
            self.publishParticipants()
        }
    }

    fileprivate func publishStage(from requests: [RtkRemoteParticipant]) {
        let mapped = requests.map {
            StudioStageRequest(userId: $0.userId, peerId: $0.id, name: $0.name)
        }
        delegate?.meetingDidUpdateStageRequests(mapped)
    }
}
