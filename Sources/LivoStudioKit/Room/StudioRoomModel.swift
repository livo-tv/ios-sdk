import Foundation
import LivoStudioAPI
import UIKit

@MainActor
public final class StudioRoomModel: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case connecting
        case waitlisted
        case rejected
        case inRoom
        case ended
        case left
        case failed(String)

        public var isTerminal: Bool {
            switch self {
            case .ended, .left, .rejected, .failed:
                return true
            case .connecting, .waitlisted, .inRoom:
                return false
            }
        }
    }

    @Published public private(set) var session: StudioSession
    @Published public private(set) var phase: Phase = .connecting
    @Published public private(set) var participants: [StudioParticipant] = []
    @Published public private(set) var waitlist: [StudioWaitlistedGuest] = []
    @Published public private(set) var messages: [StudioChatMessage] = []
    @Published public private(set) var stageRequests: [StudioStageRequest] = []
    @Published public private(set) var cameraOn = true
    @Published public private(set) var micOn = true
    @Published public private(set) var screenShareOn = false
    @Published public private(set) var streamStatus: String
    @Published public private(set) var egressPending = false
    @Published public private(set) var publishing = false
    @Published public private(set) var stopping = false
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var liveStartedAt: Date?
    @Published public private(set) var toasts: [StudioToast] = []
    @Published public private(set) var unreadChat = 0
    @Published public private(set) var selfStageStatus: StudioStageStatus?
    @Published public private(set) var activeSpeakerId: String?
    @Published public private(set) var audioDevices: [StudioMediaDevice] = []
    @Published public private(set) var videoDevices: [StudioMediaDevice] = []
    @Published public private(set) var selectedAudioId: String?
    @Published public private(set) var selectedVideoId: String?
    @Published public private(set) var rendererRevision = 0
    @Published public var confirmStop = false
    @Published public var showingSettings = false
    @Published public var pendingConfirm: PendingConfirm?
    @Published public var showingMore = false
    @Published public var selectedTab: SideTab? {
        didSet {
            if selectedTab == .chat { unreadChat = 0 }
        }
    }

    public func toggleSideTab(_ tab: SideTab) {
        selectedTab = selectedTab == tab ? nil : tab
    }

    public enum SideTab: String, CaseIterable, Identifiable, Sendable {
        case people
        case chat
        public var id: String { rawValue }
    }

    public enum PendingConfirm: Identifiable, Equatable {
        case kick(StudioParticipant)
        case mute(StudioParticipant)
        case stopCamera(StudioParticipant)
        case stopScreen(StudioParticipant)
        case takeOffStage(StudioParticipant)

        public var id: String {
            switch self {
            case let .kick(participant): "kick:\(participant.id)"
            case let .mute(participant): "mute:\(participant.id)"
            case let .stopCamera(participant): "camera:\(participant.id)"
            case let .stopScreen(participant): "screen:\(participant.id)"
            case let .takeOffStage(participant): "stage:\(participant.id)"
            }
        }
    }

    public enum AdmitAs: String, Sendable {
        case panelist
        case audience
    }

    public let apiURL: URL
    public var onEvent: ((StudioEvent) -> Void)?

    let meeting: MeetingControlling
    private var control: StudioControlClient?
    private var statusTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var idleTimerDisabled = false
    private var knownWaitlistIds = Set<String>()
    private var primedWaitlist = false
    private var knownStageRequestIds = Set<String>()
    private var toastTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingPanelists = Set<String>()
    private var cameraPausedForBackground = false
    private var wasBackgrounded = false
    private var reconnecting = false
    private var grantVerifyTasks: [String: Task<Void, Never>] = [:]
    private var joinStageWatchdog: Task<Void, Never>?
    private var signalingGraceTask: Task<Void, Never>?
    private var rendererRetryTask: Task<Void, Never>?
    private var backgroundTaskId: UUID?
    private let backgroundTasks: BackgroundTaskHolding
    private let defaults: UserDefaults
    var signalingGraceInterval: Duration = .milliseconds(300)
    var signalingGraceAttempts = 20
    var rendererRetryDelay: Duration = .milliseconds(500)
    var rendererRetryLimit = 6
    var joinStageWatchdogInterval: Duration = .seconds(1)
    static let hostTileHintKey = "livo.studio.hostTileHintShown"

    public var isModerator: Bool { session.role == .moderator }
    public var canPublish: Bool { isModerator && streamStatus == "preview" }
    public var isLive: Bool { streamStatus == "public" }
    public var canStop: Bool { isModerator && (streamStatus == "preview" || streamStatus == "public") }
    public var selfParticipant: StudioParticipant? { participants.first(where: \.isSelf) }
    public var selfUserId: String? { selfParticipant?.userId }
    public var stageParticipants: [StudioParticipant] {
        participants.filter { StudioStageLayout.isOnStage($0.stageStatus) }
    }
    public var audienceParticipants: [StudioParticipant] {
        participants.filter { !StudioStageLayout.isOnStage($0.stageStatus) }
    }
    public var selfOnStage: Bool {
        StudioStageLayout.isOnStage(selfStageStatus ?? selfParticipant?.stageStatus)
    }
    public var canUseMediaControls: Bool { isModerator || selfOnStage }
    public var peopleBadge: Int { waitlist.count + stageRequests.count }
    public var stageArrangement: StudioStageArrangement {
        StudioStageLayout.arrange(
            tiles: StudioStageLayout.expand(stageParticipants),
            activeSpeakerId: activeSpeakerId
        )
    }

    public init(
        session: StudioSession,
        apiURL: URL = LivoAPIConfiguration.productionAPIURL,
        meeting: MeetingControlling? = nil,
        defaults: UserDefaults = .standard,
        backgroundTasks: BackgroundTaskHolding? = nil,
        onEvent: ((StudioEvent) -> Void)? = nil
    ) {
        self.session = session
        self.apiURL = apiURL
        self.meeting = meeting ?? MeetingControllerFactory.makeDefault()
        self.defaults = defaults
        self.backgroundTasks = backgroundTasks ?? UIApplicationBackgroundTaskHolder()
        self.onEvent = onEvent
        streamStatus = session.stream.status
        if let token = session.studioControlToken {
            control = StudioControlClient(token: token, apiURL: apiURL)
        }
        self.meeting.delegate = self
    }

    public func start() async {
        phase = .connecting
        StudioAudioSession.configure()
        do {
            try await meeting.join(
                authToken: session.authToken,
                enableAudio: true,
                enableVideo: true
            )
            setKeepAwake(true)
            await startEgressIfNeeded()
            startStatusPolling()
            startControlRefresh()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func stopConfirmed() async {
        confirmStop = false
        guard isModerator else {
            leave()
            return
        }
        stopping = true
        do {
            _ = try await control?.stop()
            streamStatus = "ended"
            onEvent?(.ended(streamId: session.stream.id))
            meeting.leave()
            phase = .ended
        } catch {
            presentStatus(error.localizedDescription)
        }
        stopping = false
        setKeepAwake(false)
        StudioAudioSession.relinquish()
    }

    public func leave() {
        meeting.leave()
        phase = .left
        onEvent?(.left(streamId: session.stream.id))
        setKeepAwake(false)
        statusTask?.cancel()
        refreshTask?.cancel()
        endBackgroundTask()
        StudioAudioSession.relinquish()
    }

    /// Host apps present the room in a cover/sheet. Close on a terminal
    /// phase must dismiss that presentation — `leave()` alone only re-sets `.left`.
    public func dismissRoom() {
        switch phase {
        case .left, .ended:
            onEvent?(phase == .ended ? .ended(streamId: session.stream.id) : .left(streamId: session.stream.id))
        default:
            leave()
        }
    }

    public func pauseOutgoingCamera() {
        wasBackgrounded = true
        guard cameraOn, !cameraPausedForBackground else { return }
        cameraPausedForBackground = true
        meeting.setCameraEnabled(false)
    }

    public func resumeOutgoingCamera() {
        cameraPausedForBackground = false
        guard cameraOn else { return }
        meeting.setCameraEnabled(false)
        meeting.setCameraEnabled(true)
    }

    public func handleSceneBackgrounded() {
        beginBackgroundTaskIfNeeded()
        pauseOutgoingCamera()
    }

    public func handleSceneBecameActive() async {
        endBackgroundTask()
        let backgrounded = wasBackgrounded
        if cameraPausedForBackground || backgrounded {
            wasBackgrounded = false
            resumeOutgoingCamera()
        }
        guard phase == .inRoom, backgrounded else { return }
        await recoverSignalingIfNeeded()
    }

    public func reconnect() async {
        guard !reconnecting else { return }
        switch phase {
        case .ended, .left, .rejected:
            return
        case .connecting, .waitlisted, .inRoom, .failed:
            break
        }
        reconnecting = true
        meeting.leave()
        phase = .connecting
        StudioAudioSession.configure()
        do {
            try await meeting.join(
                authToken: session.authToken,
                enableAudio: micOn,
                enableVideo: cameraOn
            )
            setKeepAwake(true)
            await startEgressIfNeeded()
            startStatusPolling()
            startControlRefresh()
        } catch {
            phase = .failed(error.localizedDescription)
            setKeepAwake(false)
        }
        reconnecting = false
    }

    public func toggleCamera() {
        cameraOn.toggle()
        if cameraOn {
            cameraPausedForBackground = false
        }
        meeting.setCameraEnabled(cameraOn)
    }

    public func toggleMic() {
        micOn.toggle()
        meeting.setMicrophoneEnabled(micOn)
    }

    public func switchCamera() {
        meeting.switchCamera()
    }

    public func toggleScreenShare() {
        if screenShareOn {
            meeting.disableScreenShare()
        } else {
            meeting.enableScreenShare()
        }
    }

    public func publish() async {
        guard canPublish else { return }
        publishing = true
        do {
            let result = try await control?.publish()
            if let status = result?.stream.status {
                streamStatus = status
            } else {
                streamStatus = "public"
            }
            liveStartedAt = Date()
            onEvent?(.live(streamId: session.stream.id))
        } catch {
            presentStatus(error.localizedDescription)
        }
        publishing = false
    }

    public func admit(_ guest: StudioWaitlistedGuest) {
        admit(guest, as: .panelist)
    }

    public func admit(_ guest: StudioWaitlistedGuest, as role: AdmitAs) {
        if role == .panelist {
            queuePanelist(guest)
        }
        meeting.acceptWaitingRoom(id: guest.id)
        if role == .panelist {
            grantPendingIfPresent(matching: guest)
        }
    }

    public func admitAll(as role: AdmitAs) {
        let waiting = waitlist
        if role == .panelist {
            waiting.forEach(queuePanelist)
        }
        meeting.acceptAllWaitingRoom(ids: waiting.map(\.id))
        if role == .panelist {
            waiting.forEach(grantPendingIfPresent)
        }
    }

    public func deny(_ guest: StudioWaitlistedGuest) {
        meeting.rejectWaitingRoom(id: guest.id)
    }

    public func kick(_ participant: StudioParticipant) {
        meeting.kick(id: participant.id)
    }

    public func togglePin(_ participant: StudioParticipant) {
        if participant.pinned {
            meeting.unpin(id: participant.id)
        } else {
            meeting.pin(id: participant.id)
        }
    }

    public func sendChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        meeting.sendChat(trimmed)
    }

    public func requestStage() {
        meeting.requestStage()
    }

    public func cancelStageRequest() {
        meeting.cancelStageRequest()
    }

    public func joinStage() {
        meeting.joinStage()
    }

    public func leaveStage() {
        if !canTakeOffAir(selfParticipant) {
            pushToast("Can't leave the stage — you are the last person on air", kind: .warning)
            return
        }
        meeting.leaveStage()
    }

    public func grantStage(_ request: StudioStageRequest) {
        meeting.grantStage(id: request.stageId)
    }

    public func denyStage(_ request: StudioStageRequest) {
        meeting.denyStage(id: request.stageId)
    }

    public func bringOnAir(_ participant: StudioParticipant) {
        meeting.grantStage(id: participant.stageId)
    }

    public func takeOffStage(_ participant: StudioParticipant) {
        if !canTakeOffAir(participant) {
            pushToast("Can't take the last person off air while live", kind: .warning)
            return
        }
        meeting.takeOffStage(id: participant.stageId)
        pendingConfirm = nil
    }

    public func canTakeOffAir(_ participant: StudioParticipant?) -> Bool {
        guard let participant else { return true }
        return StudioStageLayout.canTakeOffAir(
            participants: participants,
            participantId: participant.id,
            isLive: isLive
        )
    }

    public func confirmKick() {
        if case let .kick(participant) = pendingConfirm {
            meeting.kick(id: participant.id)
        }
        pendingConfirm = nil
    }

    public func confirmMute() {
        if case let .mute(participant) = pendingConfirm {
            meeting.muteRemoteAudio(id: participant.id)
            sendHostMedia(kind: "audio", to: participant)
        }
        pendingConfirm = nil
    }

    public func confirmStopCamera() {
        if case let .stopCamera(participant) = pendingConfirm {
            meeting.disableRemoteVideo(id: participant.id)
            sendHostMedia(kind: "video", to: participant)
        }
        pendingConfirm = nil
    }

    public func confirmStopScreen() {
        if case let .stopScreen(participant) = pendingConfirm {
            sendHostMedia(kind: "screen", to: participant)
        }
        pendingConfirm = nil
    }

    public func videoView(for tile: StudioDisplayTile) -> UIView? {
        guard tile.kind != .idle else { return nil }
        let view = meeting.videoView(for: tile.participant.id, screenShare: tile.kind == .screen)
        if view == nil {
            scheduleRendererRetry()
        }
        return view
    }

    public func videoView(for participant: StudioParticipant, screenShare: Bool = false) -> UIView? {
        meeting.videoView(for: participant.id, screenShare: screenShare)
    }

    public func refreshDevices() {
        audioDevices = meeting.audioDevices()
        videoDevices = meeting.videoDevices()
        selectedAudioId = meeting.selectedAudioDeviceId()
        selectedVideoId = meeting.selectedVideoDeviceId()
    }

    public func selectDevice(_ device: StudioMediaDevice) {
        switch device.kind {
        case .audio:
            meeting.setAudioDevice(id: device.id)
            selectedAudioId = device.id
        case .video:
            meeting.setVideoDevice(id: device.id)
            selectedVideoId = device.id
        }
    }

    public func dismissToast(id: UUID) {
        toastTasks[id]?.cancel()
        toastTasks[id] = nil
        toasts.removeAll { $0.id == id }
    }

    public func pushToast(_ message: String, kind: StudioToast.Kind = .info) {
        presentToast(message, kind: kind, sound: nil)
    }

    func presentToast(_ message: String, kind: StudioToast.Kind = .info, sound: StudioSoundKind? = nil) {
        let toast = StudioToast(message: message, kind: kind)
        toasts.append(toast)
        if toasts.count > 4 {
            let dropped = toasts.removeFirst()
            toastTasks[dropped.id]?.cancel()
            toastTasks[dropped.id] = nil
        }
        if let sound { StudioSounds.play(sound) }
        toastTasks[toast.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                self?.dismissToast(id: toast.id)
            }
        }
    }

    private func presentStatus(_ message: String) {
        statusMessage = message
        pushToast(message, kind: .warning)
    }

    private func sendHostMedia(kind: String, to participant: StudioParticipant) {
        var payload = ["type": "host-media", "kind": kind]
        if let userId = participant.userId, !userId.isEmpty {
            payload["userId"] = userId
        } else {
            payload["userId"] = participant.id
        }
        meeting.sendBroadcast(type: "host-media", payload: payload)
    }

    private func queuePanelist(_ guest: StudioWaitlistedGuest) {
        if let userId = guest.userId, !userId.isEmpty {
            pendingPanelists.insert(userId)
        }
        pendingPanelists.insert(guest.id)
    }

    private func grantPendingIfPresent(matching guest: StudioWaitlistedGuest) {
        let match = participants.first {
            $0.id == guest.id || $0.userId == guest.id || $0.userId == guest.userId
        }
        if let match { takeAndGrant(match) }
    }

    private func takeAndGrant(_ participant: StudioParticipant) {
        let keys = [participant.userId, participant.id].compactMap { $0 }.filter { !$0.isEmpty }
        guard keys.contains(where: { pendingPanelists.contains($0) }) else { return }
        keys.forEach { pendingPanelists.remove($0) }
        meeting.grantStage(id: participant.stageId)
        scheduleGrantVerify(participant)
    }

    private func scheduleGrantVerify(_ participant: StudioParticipant) {
        let key = participant.stageId
        grantVerifyTasks[key]?.cancel()
        grantVerifyTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled else { return }
            let match = self.participants.first {
                $0.id == participant.id || $0.stageId == participant.stageId
            }
            guard let match, !StudioStageLayout.isOnStage(match.stageStatus) else { return }
            self.meeting.grantStage(id: match.stageId)
        }
    }

    /// One watchdog retry. Tests call this directly so they do not wait on the 1s Task.
    func performJoinStageWatchdogTick() {
        guard selfStageStatus == .acceptedToJoinStage else { return }
        meeting.joinStage()
    }

    private func startJoinStageWatchdog() {
        joinStageWatchdog?.cancel()
        joinStageWatchdog = Task { [weak self] in
            for _ in 0 ..< 30 {
                let interval = self?.joinStageWatchdogInterval ?? .seconds(1)
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await self?.performJoinStageWatchdogTick()
            }
            guard !Task.isCancelled else { return }
            await self?.finishJoinStageWatchdogIfStillAccepted()
        }
    }

    private func finishJoinStageWatchdogIfStillAccepted() {
        guard selfStageStatus == .acceptedToJoinStage else { return }
        pushToast("Couldn't join the stage automatically. Tap Joining stage to retry.", kind: .warning)
    }

    private func stopJoinStageWatchdog() {
        joinStageWatchdog?.cancel()
        joinStageWatchdog = nil
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTaskId == nil else { return }
        let id = backgroundTasks.begin("livo.studio") { [weak self] in
            Task { @MainActor in
                self?.backgroundTaskId = nil
            }
        }
        backgroundTaskId = id
    }

    private func endBackgroundTask() {
        guard let id = backgroundTaskId else { return }
        backgroundTaskId = nil
        backgroundTasks.end(id)
    }

    private func recoverSignalingIfNeeded() async {
        switch meeting.signalingState {
        case .connected:
            return
        case .failed:
            pushToast("Reconnecting…", kind: .warning)
            await reconnect()
        case .reconnecting, .disconnected:
            signalingGraceTask?.cancel()
            signalingGraceTask = Task { [weak self] in
                guard let self else { return }
                for _ in 0 ..< self.signalingGraceAttempts {
                    try? await Task.sleep(for: self.signalingGraceInterval)
                    guard !Task.isCancelled, self.phase == .inRoom else { return }
                    switch self.meeting.signalingState {
                    case .connected:
                        return
                    case .failed:
                        self.pushToast("Reconnecting…", kind: .warning)
                        await self.reconnect()
                        return
                    case .reconnecting, .disconnected:
                        continue
                    }
                }
                guard !Task.isCancelled, self.phase == .inRoom else { return }
                if self.meeting.signalingState != .connected {
                    self.pushToast("Reconnecting…", kind: .warning)
                    await self.reconnect()
                }
            }
            await signalingGraceTask?.value
        }
    }

    private func scheduleRendererRetry() {
        guard rendererRetryTask == nil else { return }
        rendererRetryTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0 ..< self.rendererRetryLimit {
                try? await Task.sleep(for: self.rendererRetryDelay)
                guard !Task.isCancelled else { return }
                guard self.hasPendingRenderers() else {
                    self.rendererRetryTask = nil
                    return
                }
                self.rendererRevision += 1
            }
            self.rendererRetryTask = nil
        }
    }

    private func hasPendingRenderers() -> Bool {
        StudioStageLayout.expand(stageParticipants).contains { tile in
            tile.kind != .idle && meeting.videoView(for: tile.participant.id, screenShare: tile.kind == .screen) == nil
        }
    }

    private func showHostTileHintIfNeeded() {
        guard isModerator, !defaults.bool(forKey: Self.hostTileHintKey) else { return }
        defaults.set(true, forKey: Self.hostTileHintKey)
        pushToast("Tip: long-press a participant tile for host controls")
    }

    public func tearDown() {
        statusTask?.cancel()
        refreshTask?.cancel()
        toastTasks.values.forEach { $0.cancel() }
        toastTasks.removeAll()
        grantVerifyTasks.values.forEach { $0.cancel() }
        grantVerifyTasks.removeAll()
        stopJoinStageWatchdog()
        signalingGraceTask?.cancel()
        signalingGraceTask = nil
        rendererRetryTask?.cancel()
        rendererRetryTask = nil
        endBackgroundTask()
        setKeepAwake(false)
        StudioAudioSession.relinquish()
    }

    private func startEgressIfNeeded() async {
        guard isModerator, let control else { return }
        egressPending = true
        do {
            _ = try await control.livestream()
        } catch {
            presentStatus(error.localizedDescription)
        }
        egressPending = false
    }

    private func startStatusPolling() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let next = try? await getPublicStreamStatus(
                    streamId: self.session.stream.id,
                    apiURL: self.apiURL
                ) {
                    await MainActor.run {
                        self.applyStreamStatus(next)
                    }
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func startControlRefresh() {
        refreshTask?.cancel()
        guard isModerator else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30 * 60))
                guard let self, !Task.isCancelled else { return }
                _ = try? await self.control?.refresh()
            }
        }
    }

    private func applyStreamStatus(_ status: String?) {
        guard let status, status != streamStatus else { return }
        let previous = streamStatus
        streamStatus = status
        if status == "public", previous != "public" {
            liveStartedAt = liveStartedAt ?? Date()
            onEvent?(.live(streamId: session.stream.id))
        }
        if status == "ended" || status == "error" {
            phase = .ended
            onEvent?(.ended(streamId: session.stream.id))
            setKeepAwake(false)
        }
    }

    private func setKeepAwake(_ enabled: Bool) {
        guard idleTimerDisabled != enabled else { return }
        idleTimerDisabled = enabled
        UIApplication.shared.isIdleTimerDisabled = enabled
    }
}

extension StudioRoomModel: MeetingControllerDelegate {
    public func meetingDidJoin() {
        if phase != .inRoom {
            phase = .inRoom
            onEvent?(.joined(streamId: session.stream.id))
            showHostTileHintIfNeeded()
        }
        if selfStageStatus == .acceptedToJoinStage {
            meeting.joinStage()
            startJoinStageWatchdog()
        }
    }

    public func meetingDidWaitlist() {
        phase = .waitlisted
    }

    public func meetingWasRejected() {
        phase = .rejected
        setKeepAwake(false)
    }

    public func meetingDidDisconnect(reason: MeetingDisconnectReason) {
        guard !reconnecting else { return }
        guard !phase.isTerminal else { return }
        switch reason {
        case .left:
            phase = .left
            onEvent?(.left(streamId: session.stream.id))
        case .kicked:
            phase = .failed("You were removed from the studio")
        case .ended:
            phase = .ended
            onEvent?(.ended(streamId: session.stream.id))
        case let .failed(message):
            phase = .failed(message)
        }
        setKeepAwake(false)
    }

    public func meetingDidUpdateParticipants(_ participants: [StudioParticipant]) {
        if self.participants != participants {
            self.participants = participants
        }
        if !pendingPanelists.isEmpty {
            participants.forEach(takeAndGrant)
        }
        if hasPendingRenderers() {
            scheduleRendererRetry()
        }
    }

    public func meetingDidUpdateWaitlist(_ guests: [StudioWaitlistedGuest]) {
        if waitlist != guests {
            if isModerator {
                if !primedWaitlist {
                    primedWaitlist = true
                    if !guests.isEmpty { selectedTab = .people }
                } else {
                    for guest in guests where !knownWaitlistIds.contains(guest.id) {
                        presentToast("\(guest.name) is knocking", sound: .request)
                        selectedTab = .people
                    }
                }
            }
            knownWaitlistIds = Set(guests.map(\.id))
            waitlist = guests
        }
    }

    public func meetingDidReceiveChat(_ message: StudioChatMessage) {
        messages.append(message)
        if messages.count > 200 {
            messages.removeFirst(messages.count - 200)
        }
        if selectedTab != .chat, message.userId != selfUserId {
            unreadChat += 1
            StudioSounds.play(.chat)
        }
    }

    public func meetingDidUpdateStageRequests(_ requests: [StudioStageRequest]) {
        if isModerator {
            for request in requests where !knownStageRequestIds.contains(request.id) {
                presentToast("\(request.name) wants to join the stage", sound: .request)
            }
        }
        knownStageRequestIds = Set(requests.map(\.id))
        if stageRequests != requests {
            stageRequests = requests
        }
    }

    public func meetingMediaDidChange(cameraOn: Bool, micOn: Bool, screenShareOn: Bool) {
        if !cameraPausedForBackground, self.cameraOn != cameraOn { self.cameraOn = cameraOn }
        if self.micOn != micOn { self.micOn = micOn }
        if self.screenShareOn != screenShareOn { self.screenShareOn = screenShareOn }
    }

    public func meetingDidUpdateActiveSpeaker(id: String?) {
        if activeSpeakerId != id { activeSpeakerId = id }
    }

    public func meetingSelfStageDidChange(_ status: StudioStageStatus?) {
        let previous = selfStageStatus
        guard previous != status else { return }
        selfStageStatus = status
        if status == .acceptedToJoinStage {
            meeting.joinStage()
            startJoinStageWatchdog()
        } else {
            stopJoinStageWatchdog()
        }
        guard !isModerator else { return }
        if previous == .requestedToJoinStage {
            if status == .acceptedToJoinStage || status == .onStage {
                presentToast("You're approved to join the stage", kind: .success)
            } else if status == .offStage {
                presentToast("Stage request was denied", kind: .warning)
            }
        }
    }

    public func meetingDidReceiveBroadcast(_ message: StudioBroadcastMessage) {
        switch message {
        case let .hostMedia(kind, targetUserId):
            if let targetUserId, !isBroadcastForSelf(targetUserId) { return }
            switch kind {
            case .audio:
                presentToast("The host muted you")
            case .video:
                presentToast("The host stopped your camera")
            case .screen:
                meeting.disableScreenShare()
                presentToast("The host stopped your screen share")
            }
        }
    }

    public func meetingDidFailScreenShare(reason: String) {
        screenShareOn = false
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        presentStatus(trimmed.isEmpty ? "Screen share could not start" : trimmed)
    }

    public func meetingDidWarn(_ message: String) {
        pushToast(message, kind: .warning)
    }

    public func meetingDidUpdateDevices() {
        refreshDevices()
    }

    private func isBroadcastForSelf(_ targetUserId: String) -> Bool {
        targetUserId == selfUserId
            || targetUserId == selfParticipant?.id
            || targetUserId == selfParticipant?.userId
    }
}
