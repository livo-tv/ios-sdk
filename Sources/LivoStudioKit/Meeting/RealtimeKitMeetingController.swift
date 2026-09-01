import Foundation
import LivoStudioAPI
import UIKit

/// Main-actor facade over `RealtimeKitEngine`. Signatures stay sync so
/// `StudioRoomModel` does not change; RTK work runs on the serial engine.
@MainActor
public final class RealtimeKitMeetingController: NSObject, MeetingControlling {
    public weak var delegate: MeetingControllerDelegate?

    public private(set) var signalingState: StudioSignalingState = .disconnected

    private let engine = RealtimeKitEngine()
    private let videoViews = StudioVideoRendererCache()
    private var cachedAudio: [StudioMediaDevice] = []
    private var cachedVideo: [StudioMediaDevice] = []
    private var cachedSelectedAudio: String?
    private var cachedSelectedVideo: String?

    override public init() {
        super.init()
    }

    public func join(authToken: String, enableAudio: Bool, enableVideo: Bool) async throws {
        await engine.attachHost(self)
        try await engine.join(authToken: authToken, enableAudio: enableAudio, enableVideo: enableVideo)
    }

    public func leave() {
        signalingState = .disconnected
        videoViews.removeAll()
        cachedAudio = []
        cachedVideo = []
        cachedSelectedAudio = nil
        cachedSelectedVideo = nil
        Task { await engine.leave() }
    }

    public func setCameraEnabled(_ enabled: Bool) {
        Task { await engine.setCameraEnabled(enabled) }
    }

    public func setMicrophoneEnabled(_ enabled: Bool) {
        Task { await engine.setMicrophoneEnabled(enabled) }
    }

    public func switchCamera() {
        Task { await engine.switchCamera() }
    }

    public func enableScreenShare() {
        Task { await engine.enableScreenShare() }
    }

    public func disableScreenShare() {
        Task { await engine.disableScreenShare() }
    }

    public func acceptWaitingRoom(id: String) {
        Task { await engine.acceptWaitingRoom(id: id) }
    }

    public func rejectWaitingRoom(id: String) {
        Task { await engine.rejectWaitingRoom(id: id) }
    }

    public func acceptAllWaitingRoom(ids: [String]) {
        Task { await engine.acceptAllWaitingRoom(ids: ids) }
    }

    public func kick(id: String) {
        Task { await engine.kick(id: id) }
    }

    public func pin(id: String) {
        Task { await engine.pin(id: id) }
    }

    public func unpin(id: String) {
        Task { await engine.unpin(id: id) }
    }

    public func sendChat(_ text: String) {
        Task { await engine.sendChat(text) }
    }

    public func requestStage() {
        Task { await engine.requestStage() }
    }

    public func cancelStageRequest() {
        Task { await engine.cancelStageRequest() }
    }

    public func joinStage() {
        Task { await engine.joinStage() }
    }

    public func leaveStage() {
        Task { await engine.leaveStage() }
    }

    public func grantStage(id: String) {
        Task { await engine.grantStage(id: id) }
    }

    public func denyStage(id: String) {
        Task { await engine.denyStage(id: id) }
    }

    public func takeOffStage(id: String) {
        Task { await engine.takeOffStage(id: id) }
    }

    public func muteRemoteAudio(id: String) {
        Task { await engine.muteRemoteAudio(id: id) }
    }

    public func disableRemoteVideo(id: String) {
        Task { await engine.disableRemoteVideo(id: id) }
    }

    public func sendBroadcast(type: String, payload: [String: String]) {
        Task { await engine.sendBroadcast(type: type, payload: payload) }
    }

    public func audioDevices() -> [StudioMediaDevice] { cachedAudio }

    public func videoDevices() -> [StudioMediaDevice] { cachedVideo }

    public func selectedAudioDeviceId() -> String? { cachedSelectedAudio }

    public func selectedVideoDeviceId() -> String? { cachedSelectedVideo }

    public func setAudioDevice(id: String) {
        cachedSelectedAudio = id
        Task { await engine.setAudioDevice(id: id) }
    }

    public func setVideoDevice(id: String) {
        cachedSelectedVideo = id
        Task { await engine.setVideoDevice(id: id) }
    }

    public func videoView(for participantId: String, screenShare: Bool) -> UIView? {
        if let cached = videoViews.view(for: participantId, screenShare: screenShare) {
            return cached
        }
        Task { await engine.requestRenderer(participantId: participantId, screenShare: screenShare) }
        return nil
    }

    /// RTK updates can land during a SwiftUI layout pass. Hop a turn.
    private func enqueueDelegate(_ work: @escaping () -> Void) {
        DispatchQueue.main.async { work() }
    }
}

extension RealtimeKitMeetingController: RealtimeKitEngineDelegate {
    func engineDidJoin() {
        enqueueDelegate { [weak self] in self?.delegate?.meetingDidJoin() }
    }

    func engineDidWaitlist() {
        enqueueDelegate { [weak self] in self?.delegate?.meetingDidWaitlist() }
    }

    func engineWasRejected() {
        enqueueDelegate { [weak self] in self?.delegate?.meetingWasRejected() }
    }

    func engineDidDisconnect(reason: MeetingDisconnectReason) {
        enqueueDelegate { [weak self] in self?.delegate?.meetingDidDisconnect(reason: reason) }
    }

    func engineDidUpdateParticipants(_ participants: [StudioParticipant]) {
        enqueueDelegate { [weak self] in self?.delegate?.meetingDidUpdateParticipants(participants) }
    }

    func engineDidUpdateWaitlist(_ guests: [StudioWaitlistedGuest]) {
        enqueueDelegate { [weak self] in self?.delegate?.meetingDidUpdateWaitlist(guests) }
    }

    func engineDidReceiveChat(_ message: StudioChatMessage) {
        enqueueDelegate { [weak self] in self?.delegate?.meetingDidReceiveChat(message) }
    }

    func engineDidUpdateStageRequests(_ requests: [StudioStageRequest]) {
        enqueueDelegate { [weak self] in self?.delegate?.meetingDidUpdateStageRequests(requests) }
    }

    func engineMediaDidChange(cameraOn: Bool, micOn: Bool, screenShareOn: Bool) {
        enqueueDelegate { [weak self] in
            self?.delegate?.meetingMediaDidChange(
                cameraOn: cameraOn,
                micOn: micOn,
                screenShareOn: screenShareOn
            )
        }
    }

    func engineDidUpdateActiveSpeaker(id: String?) {
        enqueueDelegate { [weak self] in self?.delegate?.meetingDidUpdateActiveSpeaker(id: id) }
    }

    func engineSelfStageDidChange(_ status: StudioStageStatus?) {
        enqueueDelegate { [weak self] in self?.delegate?.meetingSelfStageDidChange(status) }
    }

    func engineDidReceiveBroadcast(_ message: StudioBroadcastMessage) {
        enqueueDelegate { [weak self] in self?.delegate?.meetingDidReceiveBroadcast(message) }
    }

    func engineDidFailScreenShare(reason: String) {
        enqueueDelegate { [weak self] in self?.delegate?.meetingDidFailScreenShare(reason: reason) }
    }

    func engineDidUpdateDevices(
        audio: [StudioMediaDevice],
        video: [StudioMediaDevice],
        selectedAudio: String?,
        selectedVideo: String?
    ) {
        cachedAudio = audio
        cachedVideo = video
        cachedSelectedAudio = selectedAudio
        cachedSelectedVideo = selectedVideo
        enqueueDelegate { [weak self] in self?.delegate?.meetingDidUpdateDevices() }
    }

    func engineDidWarn(_ message: String) {
        enqueueDelegate { [weak self] in self?.delegate?.meetingDidWarn(message) }
    }

    func engineDidUpdateSignaling(_ state: StudioSignalingState) {
        signalingState = state
    }

    func engineInvalidateRenderer(id: String, userId: String?, screenShare: Bool) {
        videoViews.invalidate(participantId: id, screenShare: screenShare)
        if let userId, !userId.isEmpty, userId != id {
            videoViews.invalidate(participantId: userId, screenShare: screenShare)
        }
    }

    func engineInvalidateAllRenderers(id: String, userId: String?) {
        videoViews.invalidateAll(for: id)
        if let userId, !userId.isEmpty, userId != id {
            videoViews.invalidateAll(for: userId)
        }
    }

    func engineClearRenderers() {
        videoViews.removeAll()
    }

    func engineStoreRenderer(_ view: UIView?, participantId: String, screenShare: Bool) {
        if let view {
            videoViews.store(view, participantId: participantId, screenShare: screenShare)
        }
    }
}
