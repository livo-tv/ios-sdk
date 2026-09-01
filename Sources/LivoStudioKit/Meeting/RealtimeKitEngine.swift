import Foundation
import LivoStudioAPI
import RealtimeKit
import UIKit

/// Serial executor so RealtimeKit calls never overlap. The Kotlin/Native
/// bridge does not document concurrent call-in.
final class DispatchQueueSerialExecutor: SerialExecutor, @unchecked Sendable {
    let queue: DispatchQueue

    init(label: String) {
        queue = DispatchQueue(label: label)
    }

    func enqueue(_ job: UnownedJob) {
        queue.async {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}

@MainActor
protocol RealtimeKitEngineDelegate: AnyObject {
    func engineDidJoin()
    func engineDidWaitlist()
    func engineWasRejected()
    func engineDidDisconnect(reason: MeetingDisconnectReason)
    func engineDidUpdateParticipants(_ participants: [StudioParticipant])
    func engineDidUpdateWaitlist(_ guests: [StudioWaitlistedGuest])
    func engineDidReceiveChat(_ message: StudioChatMessage)
    func engineDidUpdateStageRequests(_ requests: [StudioStageRequest])
    func engineMediaDidChange(cameraOn: Bool, micOn: Bool, screenShareOn: Bool)
    func engineDidUpdateActiveSpeaker(id: String?)
    func engineSelfStageDidChange(_ status: StudioStageStatus?)
    func engineDidReceiveBroadcast(_ message: StudioBroadcastMessage)
    func engineDidFailScreenShare(reason: String)
    func engineDidUpdateDevices(
        audio: [StudioMediaDevice],
        video: [StudioMediaDevice],
        selectedAudio: String?,
        selectedVideo: String?
    )
    func engineDidWarn(_ message: String)
    func engineDidUpdateSignaling(_ state: StudioSignalingState)
    func engineInvalidateRenderer(id: String, userId: String?, screenShare: Bool)
    func engineInvalidateAllRenderers(id: String, userId: String?)
    func engineClearRenderers()
    func engineStoreRenderer(_ view: UIView?, participantId: String, screenShare: Bool)
}

/// Owns the RealtimeKit client and runs every call on a dedicated serial queue.
actor RealtimeKitEngine {
    nonisolated let executor: DispatchQueueSerialExecutor

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    private weak var host: (any RealtimeKitEngineDelegate)?
    private var meeting: RealtimeKitClient?
    private var relay: RealtimeKitListenerRelay?
    private var joining = false
    private var didJoinRoom = false
    private var pendingStageJoin = false
    private var joinStageInFlight = false

    init() {
        executor = DispatchQueueSerialExecutor(label: "tv.livo.studio.rtk")
    }

    func attachHost(_ host: any RealtimeKitEngineDelegate) {
        self.host = host
        if relay == nil {
            relay = RealtimeKitListenerRelay(engine: self)
        }
    }

    func signalingState() -> StudioSignalingState {
        Self.mapSignaling(meeting?.meta.socketConnectionState)
    }

    func join(authToken: String, enableAudio: Bool, enableVideo: Bool) async throws {
        if joining { return }
        joining = true
        let client = RealtimeKitiOSClientBuilder().build()
        meeting = client
        if relay == nil {
            relay = RealtimeKitListenerRelay(engine: self)
        }
        if let relay {
            client.addMeetingRoomEventListener(meetingRoomEventListener: relay)
            client.addParticipantsEventListener(participantsEventListener: relay)
            client.addSelfEventListener(selfEventListener: relay)
            client.addWaitlistEventListener(waitlistEventListener: relay)
            client.addChatEventListener(chatEventListener: relay)
            client.addStageEventListener(stageEventListener: relay)
            client.addDataUpdateListener(dataUpdateListener: relay)
        }

        let info = RtkMeetingInfo(authToken: authToken, enableAudio: enableAudio, enableVideo: enableVideo)
        do {
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
        } catch {
            joining = false
            detach(client)
            meeting = nil
            throw error
        }
        didJoinRoom = true
        joining = false
        publishSignaling()
        publishParticipants()
        publishWaitlist()
        publishMedia()
        publishSelfStage()
        publishDevices()
        flushPendingStageJoin()
    }

    func leave() {
        didJoinRoom = false
        pendingStageJoin = false
        joinStageInFlight = false
        joining = false
        let outgoing = meeting
        meeting = nil
        if let outgoing, let relay {
            outgoing.removeMeetingRoomEventListener(meetingRoomEventListener: relay)
            outgoing.removeParticipantsEventListener(participantsEventListener: relay)
            outgoing.removeSelfEventListener(selfEventListener: relay)
            outgoing.removeWaitlistEventListener(waitlistEventListener: relay)
            outgoing.removeChatEventListener(chatEventListener: relay)
            outgoing.removeStageEventListener(stageEventListener: relay)
            outgoing.removeDataUpdateListener(dataUpdateListener: relay)
        }
        outgoing?.leaveRoom(onSuccess: {}, onFailure: { _ in })
        notify { $0.engineClearRenderers() }
        notify { $0.engineDidUpdateSignaling(.disconnected) }
    }

    private func detach(_ client: RealtimeKitClient) {
        guard let relay else { return }
        client.removeMeetingRoomEventListener(meetingRoomEventListener: relay)
        client.removeParticipantsEventListener(participantsEventListener: relay)
        client.removeSelfEventListener(selfEventListener: relay)
        client.removeWaitlistEventListener(waitlistEventListener: relay)
        client.removeChatEventListener(chatEventListener: relay)
        client.removeStageEventListener(stageEventListener: relay)
        client.removeDataUpdateListener(dataUpdateListener: relay)
    }

    func setCameraEnabled(_ enabled: Bool) {
        if enabled {
            meeting?.localUser.enableVideo(onResult: { [weak self] _ in
                Task { await self?.publishMedia() }
            })
        } else {
            meeting?.localUser.disableVideo(onResult: { [weak self] _ in
                Task { await self?.publishMedia() }
            })
        }
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        if enabled {
            meeting?.localUser.enableAudio(onResult: { [weak self] _ in
                Task { await self?.publishMedia() }
            })
        } else {
            meeting?.localUser.disableAudio(onResult: { [weak self] _ in
                Task { await self?.publishMedia() }
            })
        }
    }

    func switchCamera() {
        meeting?.localUser.switchCamera()
    }

    func enableScreenShare() {
        meeting?.localUser.enableScreenShare(onResult: { [weak self] _ in
            Task { await self?.publishMedia() }
        })
    }

    func disableScreenShare() {
        meeting?.localUser.disableScreenShare(onResult: { [weak self] _ in
            Task { await self?.publishMedia() }
        })
    }

    func acceptWaitingRoom(id: String) {
        meeting?.participants.acceptWaitingRoomRequest(id: id)
    }

    func rejectWaitingRoom(id: String) {
        meeting?.participants.rejectWaitingRoomRequest(id: id)
    }

    func acceptAllWaitingRoom(ids: [String]) {
        for id in ids {
            meeting?.participants.acceptWaitingRoomRequest(id: id)
        }
    }

    func kick(id: String) {
        _ = remote(id)?.kick()
    }

    func pin(id: String) {
        _ = remote(id)?.pin()
    }

    func unpin(id: String) {
        _ = remote(id)?.unpin()
    }

    func sendChat(_ text: String) {
        _ = meeting?.chat.sendTextMessage(message: text)
    }

    func requestStage() {
        reportStageError(meeting?.stage.requestAccess())
    }

    func cancelStageRequest() {
        reportStageError(meeting?.stage.cancelRequestAccess())
    }

    func joinStage() {
        pendingStageJoin = true
        flushPendingStageJoin()
    }

    func leaveStage() {
        pendingStageJoin = false
        reportStageError(meeting?.stage.leave())
        publishSelfStage()
    }

    func grantStage(id: String) {
        reportStageError(meeting?.stage.grantAccess(userIds: [id]))
    }

    func denyStage(id: String) {
        reportStageError(meeting?.stage.denyAccess(userIds: [id]))
    }

    func takeOffStage(id: String) {
        reportStageError(meeting?.stage.kick(userIds: [id]))
    }

    func muteRemoteAudio(id: String) {
        _ = remote(id)?.disableAudio()
    }

    func disableRemoteVideo(id: String) {
        _ = remote(id)?.disableVideo()
    }

    func sendBroadcast(type: String, payload: [String: String]) {
        meeting?.participants.broadcastMessage(type: type, payload: payload)
    }

    func setAudioDevice(id: String) {
        guard let device = meeting?.localUser.getAudioDevices().first(where: { $0.id == id }) else { return }
        meeting?.localUser.setAudioDevice(rtkAudioDevice: device)
    }

    func setVideoDevice(id: String) {
        guard let device = meeting?.localUser.getVideoDevices().first(where: { $0.id == id }) else { return }
        meeting?.localUser.setVideoDevice(rtkVideoDevice: device)
    }

    func requestRenderer(participantId: String, screenShare: Bool) {
        guard let meeting else { return }
        let local = isLocalUser(participantId)
        let remote = remote(participantId)
        let host = host
        Task { @MainActor in
            let view: UIView?
            if local {
                view = screenShare
                    ? meeting.localUser.getScreenShareVideoView()
                    : meeting.localUser.getVideoView()
            } else {
                view = screenShare
                    ? remote?.getScreenShareVideoView()
                    : remote?.getVideoView()
            }
            host?.engineStoreRenderer(view, participantId: participantId, screenShare: screenShare)
        }
    }

    private func currentStageStatus() -> StageStatus? {
        meeting?.stage.stageStatus ?? meeting?.localUser.stageStatus
    }

    private func isStageAccepted() -> Bool {
        meeting?.stage.stageStatus == .acceptedToJoinStage
            || meeting?.localUser.stageStatus == .acceptedToJoinStage
    }

    private func isStageBusyError(_ error: StageError) -> Bool {
        let message = error.message
        return message.contains("2006")
            || message.contains("ERR2006")
            || message.localizedCaseInsensitiveContains("OFF_STAGE")
            || message.localizedCaseInsensitiveContains("concurrent")
    }

    private func flushPendingStageJoin() {
        guard didJoinRoom else { return }
        guard pendingStageJoin || isStageAccepted() else { return }
        guard !joinStageInFlight else { return }
        joinStageInFlight = true
        Task { await self.runJoinStageAttempts() }
    }

    private func runJoinStageAttempts() async {
        defer { joinStageInFlight = false }
        for attempt in 0 ..< 3 {
            if currentStageStatus() == .onStage {
                pendingStageJoin = false
                publishSelfStage()
                publishParticipants()
                return
            }
            if let error = meeting?.stage.join() {
                if isStageBusyError(error), attempt < 2 {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                reportStageError(error)
                publishSelfStage()
                return
            }
            pendingStageJoin = false
            if currentStageStatus() == .onStage {
                republishCameraIfOn()
                publishSelfStage()
                publishParticipants()
                publishMedia()
            } else {
                publishSelfStage()
            }
            return
        }
        publishSelfStage()
    }

    private func republishCameraIfOn() {
        guard meeting?.localUser.videoEnabled == true else { return }
        meeting?.localUser.disableVideo(onResult: { [weak self] _ in
            Task {
                await self?.meeting?.localUser.enableVideo(onResult: { _ in
                    Task { await self?.publishMedia() }
                })
            }
        })
    }

    private func reportStageError(_ error: StageError?) {
        guard let error else { return }
        let message = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        notify { $0.engineDidWarn(message.isEmpty ? "Stage action failed" : message) }
    }

    private func isLocalUser(_ id: String) -> Bool {
        guard let user = meeting?.localUser else { return false }
        return user.id == id || user.userId == id
    }

    private func remote(_ id: String) -> RtkRemoteParticipant? {
        if let found = meeting?.participants.joined.first(where: { $0.id == id || $0.userId == id }) {
            return found
        }
        return meeting?.participants.screenShares.first { $0.id == id || $0.userId == id }
    }

    private func notify(_ work: @escaping @MainActor (any RealtimeKitEngineDelegate) -> Void) {
        let host = host
        Task { @MainActor in
            guard let host else { return }
            work(host)
        }
    }

    fileprivate func publishMedia() {
        guard let user = meeting?.localUser else { return }
        let cameraOn = user.videoEnabled
        let micOn = user.audioEnabled
        let screenShareOn = user.screenShareEnabled
        notify {
            $0.engineMediaDidChange(cameraOn: cameraOn, micOn: micOn, screenShareOn: screenShareOn)
        }
    }

    fileprivate func publishSelfStage() {
        let mapped = Self.mapStage(meeting?.stage.stageStatus ?? meeting?.localUser.stageStatus)
        notify { $0.engineSelfStageDidChange(mapped) }
    }

    fileprivate func publishDevices() {
        let audio = (meeting?.localUser.getAudioDevices() ?? []).map { device in
            StudioMediaDevice(id: device.id, name: device.type.displayName, kind: .audio)
        }
        let video = (meeting?.localUser.getVideoDevices() ?? []).map { device in
            StudioMediaDevice(id: device.id, name: device.description, kind: .video)
        }
        let selectedAudio = meeting?.localUser.getSelectedAudioDevice()?.id
        let selectedVideo = meeting?.localUser.getSelectedVideoDevice()?.id
        notify {
            $0.engineDidUpdateDevices(
                audio: audio,
                video: video,
                selectedAudio: selectedAudio,
                selectedVideo: selectedVideo
            )
        }
    }

    fileprivate func publishSignaling() {
        let state = signalingState()
        notify { $0.engineDidUpdateSignaling(state) }
    }

    fileprivate func publishParticipants() {
        guard let meeting else { return }
        let sharingIds = Set(meeting.participants.screenShares.map(\.id))
        var tiles: [StudioParticipant] = []
        let selfUser = meeting.localUser
        tiles.append(
            Self.tile(
                id: selfUser.id,
                name: selfUser.name,
                isSelf: true,
                audio: selfUser.audioEnabled,
                video: selfUser.videoEnabled,
                screen: selfUser.screenShareEnabled || sharingIds.contains(selfUser.id),
                picture: selfUser.picture,
                userId: selfUser.userId,
                pinned: selfUser.isPinned,
                stage: selfUser.stageStatus
            )
        )
        for participant in meeting.participants.joined {
            tiles.append(
                Self.tile(
                    id: participant.id,
                    name: participant.name,
                    isSelf: false,
                    audio: participant.audioEnabled,
                    video: participant.videoEnabled,
                    screen: participant.screenShareEnabled || sharingIds.contains(participant.id),
                    picture: participant.picture,
                    userId: participant.userId,
                    pinned: participant.isPinned,
                    stage: participant.stageStatus
                )
            )
        }
        let snapshot = tiles
        notify { $0.engineDidUpdateParticipants(snapshot) }
        for tile in snapshot {
            if tile.videoEnabled {
                requestRenderer(participantId: tile.id, screenShare: false)
            }
            if tile.screenShareEnabled {
                requestRenderer(participantId: tile.id, screenShare: true)
            }
        }
    }

    fileprivate func publishWaitlist() {
        let guests = (meeting?.participants.waitlisted ?? []).map {
            StudioWaitlistedGuest(id: $0.id, name: $0.name, userId: $0.userId, picture: $0.picture)
        }
        notify { $0.engineDidUpdateWaitlist(guests) }
    }

    fileprivate func publishStage(from requests: [RtkRemoteParticipant]) {
        let mapped = requests.map {
            StudioStageRequest(userId: $0.userId, peerId: $0.id, name: $0.name)
        }
        notify { $0.engineDidUpdateStageRequests(mapped) }
    }

    fileprivate func invalidateRenderer(id: String, userId: String?, screenShare: Bool) {
        notify { $0.engineInvalidateRenderer(id: id, userId: userId, screenShare: screenShare) }
    }

    fileprivate func invalidateAllRenderers(id: String, userId: String?) {
        notify { $0.engineInvalidateAllRenderers(id: id, userId: userId) }
    }

    fileprivate func handleSocket(_ newState: SocketConnectionState) {
        guard didJoinRoom else { return }
        if newState.isReconnectionFailure {
            notify { $0.engineDidUpdateSignaling(.failed) }
            notify { $0.engineDidDisconnect(reason: .failed("Connection lost. Leave and rejoin.")) }
            return
        }
        let mapped = Self.mapSignaling(newState)
        notify { $0.engineDidUpdateSignaling(mapped) }
        switch newState.socketState {
        case .reconnecting:
            notify { $0.engineDidWarn("Reconnecting…") }
        case .disconnected, .failed:
            notify { $0.engineDidDisconnect(reason: .failed("Connection lost. Leave and rejoin.")) }
        case .connected:
            break
        @unknown default:
            break
        }
    }

    fileprivate func handleJoinedRoom() {
        didJoinRoom = true
        notify { $0.engineDidJoin() }
        publishParticipants()
        flushPendingStageJoin()
    }

    fileprivate func handleWaitList(_ status: WaitListStatus) {
        if status == .waiting {
            notify { $0.engineDidWaitlist() }
        } else if status == .rejected {
            notify { $0.engineWasRejected() }
        } else if status == .accepted {
            notify { $0.engineDidJoin() }
        }
    }

    fileprivate func handlePermissions(_ permission: SelfPermissions) {
        if permission.miscellaneous.stageAccess == .allowed {
            joinStage()
        }
    }

    fileprivate func handleChat(_ message: ChatMessage) {
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
        notify { $0.engineDidReceiveChat(mapped) }
    }

    fileprivate func handleBroadcast(type: String, payload: [String: Any]) {
        if let message = Self.parseBroadcast(type: type, payload: payload) {
            notify { $0.engineDidReceiveBroadcast(message) }
        }
    }

    fileprivate func handleScreenShares(_ screenShares: [RtkRemoteParticipant]) {
        for participant in screenShares {
            invalidateRenderer(id: participant.id, userId: participant.userId, screenShare: true)
        }
        publishParticipants()
    }

    private static func parseBroadcast(type: String, payload: [String: Any]) -> StudioBroadcastMessage? {
        let nested = payload["payload"] as? [String: Any]
        let body = nested ?? payload
        let resolvedType = (body["type"] as? String) ?? type
        guard resolvedType == "host-media" else { return nil }
        let kind = (body["kind"] as? String).flatMap(StudioBroadcastMessage.HostMediaKind.init(rawValue:))
        guard let kind else { return nil }
        let target = (body["userId"] as? String) ?? (body["targetUserId"] as? String)
        return .hostMedia(kind: kind, targetUserId: target)
    }

    private static func tile(
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

    private static func mapStage(_ status: StageStatus?) -> StudioStageStatus? {
        guard let status else { return nil }
        switch status {
        case .offStage: return .offStage
        case .requestedToJoinStage: return .requestedToJoinStage
        case .acceptedToJoinStage: return .acceptedToJoinStage
        case .onStage: return .onStage
        @unknown default: return nil
        }
    }

    private static func mapSignaling(_ state: SocketConnectionState?) -> StudioSignalingState {
        guard let state else { return .disconnected }
        if state.isReconnectionFailure { return .failed }
        switch state.socketState {
        case .connected: return .connected
        case .reconnecting: return .reconnecting
        case .disconnected: return .disconnected
        case .failed: return .failed
        @unknown default: return .disconnected
        }
    }
}

/// ObjC listener bridge. Actors cannot inherit `NSObject`, so RTK callbacks
/// land here and hop onto the engine.
final class RealtimeKitListenerRelay: NSObject, @unchecked Sendable {
    let engine: RealtimeKitEngine

    init(engine: RealtimeKitEngine) {
        self.engine = engine
    }
}

extension RealtimeKitListenerRelay: RtkMeetingRoomEventListener {
    func onActiveTabUpdate(meeting: RealtimeKitClient, activeTab: ActiveTab) {}
    func onMeetingInitCompleted(meeting: RealtimeKitClient) {}
    func onMeetingInitFailed(error: MeetingError) {}
    func onMeetingInitStarted() {}
    func onMeetingRoomJoinStarted() {}
    func onMeetingRoomJoinFailed(error: MeetingError) {}
    func onMeetingRoomLeaveStarted() {}
    func onMeetingRoomLeaveCompleted() {}
    func onMediaConnectionUpdate(update: MediaConnectionUpdate) {}

    func onSocketConnectionUpdate(newState: SocketConnectionState) {
        Task { await engine.handleSocket(newState) }
    }

    func onMeetingRoomJoinCompleted(meeting: RealtimeKitClient) {
        Task { await engine.handleJoinedRoom() }
    }

    func onMeetingEnded() {
        Task { await engine.notifyDisconnect(.ended) }
    }
}

extension RealtimeKitEngine {
    fileprivate func notifyDisconnect(_ reason: MeetingDisconnectReason) {
        notify { $0.engineDidDisconnect(reason: reason) }
    }

    fileprivate func notifyKicked() {
        notify { $0.engineDidDisconnect(reason: .kicked) }
    }

    fileprivate func notifyScreenShareFailed(_ reason: String) {
        publishMedia()
        notify { $0.engineDidFailScreenShare(reason: reason) }
    }
}

extension RealtimeKitListenerRelay: RtkParticipantsEventListener {
    func onActiveParticipantsChanged(active: [RtkRemoteParticipant]) {}
    func onActiveSpeakerChanged(participant: RtkRemoteParticipant?) {
        let id = participant?.id
        Task { await engine.notifyActiveSpeaker(id) }
    }
    func onAllParticipantsUpdated(allParticipants: [RtkParticipant]) {}
    func onNewBroadcastMessage(type: String, payload: [String: Any]) {
        Task { await engine.handleBroadcast(type: type, payload: payload) }
    }

    func onScreenShareUpdate(participant: RtkRemoteParticipant, isEnabled: Bool) {
        Task { await engine.handleRemoteScreenShare(participant) }
    }

    func onUpdate(participants: RtkParticipants) {
        Task { await engine.publishParticipantsAndWaitlist() }
    }

    func onParticipantJoin(participant: RtkRemoteParticipant) {
        Task { await engine.publishParticipants() }
    }

    func onParticipantLeave(participant: RtkRemoteParticipant) {
        Task { await engine.handleParticipantLeave(participant) }
    }

    func onAudioUpdate(participant: RtkRemoteParticipant, isEnabled: Bool) {
        Task { await engine.publishParticipants() }
    }

    func onVideoUpdate(participant: RtkRemoteParticipant, isEnabled: Bool) {
        Task { await engine.handleRemoteVideo(participant) }
    }

    func onParticipantPinned(participant: RtkRemoteParticipant) {
        Task { await engine.publishParticipants() }
    }

    func onParticipantUnpinned(participant: RtkRemoteParticipant) {
        Task { await engine.publishParticipants() }
    }
}

extension RealtimeKitEngine {
    fileprivate func notifyActiveSpeaker(_ id: String?) {
        notify { $0.engineDidUpdateActiveSpeaker(id: id) }
    }

    fileprivate func publishParticipantsAndWaitlist() {
        publishParticipants()
        publishWaitlist()
    }

    fileprivate func handleRemoteScreenShare(_ participant: RtkRemoteParticipant) {
        invalidateRenderer(id: participant.id, userId: participant.userId, screenShare: true)
        publishParticipants()
    }

    fileprivate func handleRemoteVideo(_ participant: RtkRemoteParticipant) {
        invalidateRenderer(id: participant.id, userId: participant.userId, screenShare: false)
        publishParticipants()
    }

    fileprivate func handleParticipantLeave(_ participant: RtkRemoteParticipant) {
        invalidateAllRenderers(id: participant.id, userId: participant.userId.isEmpty ? nil : participant.userId)
        publishParticipants()
    }

    fileprivate func handleLocalVideo() {
        if let user = meeting?.localUser {
            invalidateRenderer(id: user.id, userId: user.userId, screenShare: false)
        }
        publishMedia()
        publishParticipants()
    }

    fileprivate func handleLocalScreenShare() {
        if let user = meeting?.localUser {
            invalidateRenderer(id: user.id, userId: user.userId, screenShare: true)
        }
        publishMedia()
        publishParticipants()
    }
}

extension RealtimeKitListenerRelay: RtkSelfEventListener {
    func onAudioDeviceChanged(audioDevice: AudioDevice) {
        Task { await engine.publishDevices() }
    }

    func onAudioDevicesUpdated(devices: [AudioDevice]) {
        Task { await engine.publishDevices() }
    }

    func onMeetingRoomJoinedWithoutCameraPermission() {}
    func onMeetingRoomJoinedWithoutMicPermission() {}

    func onPermissionsUpdated(permission: SelfPermissions) {
        Task { await engine.handlePermissions(permission) }
    }

    func onPinned() {}
    func onUnpinned() {}

    func onScreenShareStartFailed(reason: String) {
        Task { await engine.notifyScreenShareFailed(reason) }
    }

    func onUpdate(participant: RtkSelfParticipant) {
        Task { await engine.publishMediaAndParticipants() }
    }

    func onVideoDeviceChanged(videoDevice: VideoDevice) {
        Task { await engine.publishDevices() }
    }

    func onVideoUpdate(isEnabled: Bool) {
        Task { await engine.handleLocalVideo() }
    }

    func onAudioUpdate(isEnabled: Bool) {
        Task { await engine.publishMediaAndParticipants() }
    }

    func onScreenShareUpdate(isEnabled: Bool) {
        Task { await engine.handleLocalScreenShare() }
    }

    func onRemovedFromMeeting() {
        Task { await engine.notifyKicked() }
    }

    func onWaitListStatusUpdate(waitListStatus: WaitListStatus) {
        Task { await engine.handleWaitList(waitListStatus) }
    }
}

extension RealtimeKitEngine {
    fileprivate func publishMediaAndParticipants() {
        publishMedia()
        publishParticipants()
    }
}

extension RealtimeKitListenerRelay: RtkWaitlistEventListener {
    func onWaitListParticipantJoined(participant: RtkRemoteParticipant) {
        Task { await engine.publishWaitlist() }
    }

    func onWaitListParticipantAccepted(participant: RtkRemoteParticipant) {
        Task { await engine.publishParticipantsAndWaitlist() }
    }

    func onWaitListParticipantRejected(participant: RtkRemoteParticipant) {
        Task { await engine.publishWaitlist() }
    }

    func onWaitListParticipantClosed(participant: RtkRemoteParticipant) {
        Task { await engine.publishWaitlist() }
    }
}

extension RealtimeKitListenerRelay: RtkChatEventListener {
    func onChatUpdates(messages: [ChatMessage]) {}
    func onMessageDeleted(messageId: String) {}
    func onMessageEdited(message: ChatMessage) {}
    func onMessageRateLimitReset() {}

    func onNewChatMessage(message: ChatMessage) {
        Task { await engine.handleChat(message) }
    }
}

extension RealtimeKitListenerRelay: RtkStageEventListener {
    func onNewStageAccessRequest(participant: RtkRemoteParticipant) {
        Task { await engine.publishStage(from: [participant]) }
    }

    func onPeerStageStatusUpdated(participant: RtkRemoteParticipant, oldStatus: StageStatus, newStatus: StageStatus) {
        Task { await engine.publishParticipants() }
    }

    func onRemovedFromStage() {
        Task { await engine.publishSelfStageAndParticipants() }
    }

    func onStageAccessRequestAccepted() {
        Task { await engine.joinStage() }
    }

    func onStageAccessRequestRejected() {
        Task { await engine.publishSelfStage() }
    }

    func onStageAccessRequestsUpdated(accessRequests: [RtkRemoteParticipant]) {
        Task { await engine.publishStage(from: accessRequests) }
    }

    func onStageStatusUpdated(oldStatus: StageStatus, newStatus: StageStatus) {
        Task { await engine.handleStageStatus(newStatus) }
    }
}

extension RealtimeKitEngine {
    fileprivate func publishSelfStageAndParticipants() {
        publishSelfStage()
        publishParticipants()
    }

    fileprivate func handleStageStatus(_ newStatus: StageStatus) {
        if newStatus == .acceptedToJoinStage || isStageAccepted() {
            pendingStageJoin = true
            joinStage()
        }
        publishSelfStage()
        publishParticipants()
    }
}

extension RealtimeKitListenerRelay: RtkDataUpdateListener {
    func onLivestreamUpdate(livestream: RtkLivestreamData) {}
    func onMetaUpdate(
        meetingId: String,
        meetingTitle: String,
        meetingStartedTimestamp: String,
        roomType: String,
        designToken: RtkDesignToken
    ) {}
    func onPluginsUpdates(plugins: [RtkPlugin]) {}
    func onSelfPermissionsUpdate(permission: SelfPermissions) {}

    func onScreenShareUpdate(screenShares: [RtkRemoteParticipant]) {
        Task { await engine.handleScreenShares(screenShares) }
    }
}
